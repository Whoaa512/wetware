# Wetware ↔ OpenClaw Integration

## Architecture

Two components form a read/write feedback loop between the wetware gel and agent sessions:

```
┌─────────────────┐         ┌──────────────┐         ┌─────────────┐
│  Agent Session   │◄────────│ wetware-prime │◄────────│  Wetware    │
│  (context window)│  inject │ (hook)        │  read   │  Gel        │
└────────┬────────┘         └──────────────┘         └──────▲──────┘
         │                                                   │
         │ session memory files                              │ stimulate
         ▼                                                   │
┌─────────────────┐         ┌──────────────────┐            │
│  ~/nova/memory/  │────────►│ imprint-sessions │────────────┘
│  YYYY-MM-DD.md   │  read   │ (cron, every 4h) │  auto-imprint
└─────────────────┘         └──────────────────┘
```

### wetware-prime (Hook)

**Event:** `agent:bootstrap`  
**Location:** `~/.openclaw/hooks/wetware-prime/`  
**Source:** [`example/openclaw/hooks/wetware-prime/handler.ts`](../example/openclaw/hooks/wetware-prime/handler.ts)  
**What:** Injects resonance briefing + priming orientations into session context.

Fires on every new session (manual `/new`, daily rollover, API reset). The agent
starts each session with ambient awareness of what's active in the gel.

The hook pushes a synthetic bootstrap file into `event.context.bootstrapFiles`:
```ts
ctx.bootstrapFiles.push({
  name: "WETWARE_RESONANCE.md",   // required by OpenClaw's bootstrap loader
  path: "WETWARE_RESONANCE.md",
  content,
  source: "hook:wetware-prime",
});
```

### wetware-imprint-sessions (Cron)

**Schedule:** Every 4-6 hours  
**Location:** `~/nova/scripts/wetware-imprint-sessions.sh`  
**What:** Batch-processes session memory files through `wetware auto-imprint`.

## State Tracking

The imprint cron tracks what's been processed in:
```
~/.config/wetware/imprint-state.json
```

Schema:
```json
{
  "imprinted": {
    "2026-02-24.md": {
      "ts": "2026-02-24T20:00:00Z",
      "concepts": 5
    }
  },
  "last_run": "2026-02-24T20:00:00Z"
}
```

**Why file-level tracking (not timestamp-based):**
- Timestamp comparison misses files modified after initial scan
- File-level map is idempotent — safe to re-run, won't double-imprint
- Records concept count per file for observability
- Files that match no concepts are marked `"skipped": true` so they aren't retried

**Why skip today's file:**
- Daily memory files are appended throughout the day
- Imprinting a partial file means the later content never gets imprinted
- Default: wait until the next day. Override with `--include-today`.

## Design Tradeoffs

### Why cron instead of a hook?

We considered three approaches for the imprint (write) side:

| Approach | Pros | Cons |
|----------|------|------|
| **`command:new` hook** | Natural timing (session just ended) | Doesn't fire on daily rollover — only on explicit `/new` or `/reset`. Would miss the most common session boundary. |
| **`agent:bootstrap` hook** (look backward) | Fires on all session starts including rollover | Race condition: multiple sessions roll over at 4am simultaneously. Hard to determine which previous session file belongs to which new session. `session-memory` may not have written the file yet. |
| **Cron job** ✓ | Decoupled from session lifecycle. Batch-friendly. No race conditions. Simple dedup. | Delayed feedback (up to 4h lag). Needs external state file. |

The cron approach trades immediacy for reliability. A 4-hour lag is acceptable because:
- The gel evolves slowly (concepts drift over hours/days, not minutes)
- The priming hook gives immediate read access to current state
- Batch processing is more efficient than per-session stimulation

### Why outbound-only (via session memory)?

Session memory files contain Nova's synthesized output — what she actually said and
thought, not raw user input. This is better signal because:
- Captures what the agent found salient (not everything the user said)
- No risk of external content injecting concepts through the gel
- Memory files are already summarized, reducing noise

### Token budget tradeoffs

| Budget | Content | Impact |
|--------|---------|--------|
| 1000 tokens | Top 8 concepts + mood only | Minimal context cost, just vibes |
| 2000 tokens (default) | Full briefing + priming orientations | Good balance of awareness vs cost |
| 3000+ tokens | Briefing + priming + concept descriptions | Rich but expensive per-session |

The budget is configurable via `WETWARE_PRIME_MAX_TOKENS`. At 2000 tokens, the
injection is ~2.5% of a typical 80k context window.

## Configuration

### Hook (wetware-prime)

Set via hook env in OpenClaw config:
```json
{
  "hooks": {
    "internal": {
      "entries": {
        "wetware-prime": {
          "enabled": true,
          "env": {
            "WETWARE_PRIME_MAX_TOKENS": "2000",
            "WETWARE_PRIME_ENABLED": "true"
          }
        }
      }
    }
  }
}
```

### Cron (wetware-imprint-sessions)

Environment variables:
```
WETWARE_BIN=~/bin/wetware
WETWARE_MEMORY_DIR=~/nova/memory
WETWARE_IMPRINT_MIN_LINES=20
WETWARE_IMPRINT_DEFAULT_DEPTH=3
```

## Future Considerations

- **Automatic concept discovery:** Currently `auto-imprint` only matches existing
  concepts. New topics get missed. Could add a `wetware discover` pass for files
  with many unmatched lines.
- **Inbound imprinting:** Could process user messages too, but risks prompt injection
  through the gel. Outbound-only is safer for now.
- **Real-time imprint via hook:** If OpenClaw adds `session_end` to the internal
  hook system (not just the plugin system), we could switch from cron to hook-based
  imprinting.
- **Gel state diffing:** Track gel state before/after imprint runs to measure
  actual impact on concept activation.

---

## Long-Term: Wetware Daemon (`wetwared`)

### Problem

The BEAM VM takes ~7s to cold-start. Running `wetware briefing` and `wetware priming`
as CLI commands means every `agent:bootstrap` hook adds 7-15s of latency per new session.
The current workaround is a generous 15s timeout, but this is wasteful and fragile.

### Solution: Persistent Daemon

Run wetware as a long-lived OTP application instead of an escript CLI.

**Architecture:**
```
wetwared (persistent)          openclaw hooks
┌──────────────────┐           ┌─────────────┐
│  BEAM VM (warm)  │◄──────────│ HTTP/Unix   │
│  Gel state in    │  briefing │ socket call │
│  ETS/memory      │  priming  │ ~10ms RTT   │
│  Dream scheduler │──────────►│             │
│  Imprint worker  │           └─────────────┘
└──────────────────┘
```

**Key changes:**
1. **`wetwared start`** — boots the BEAM VM once, loads gel state, listens on a Unix socket
   (e.g., `~/.config/wetware/wetware.sock`) or localhost HTTP port
2. **`wetware briefing`** (CLI) — becomes a thin client that connects to the daemon,
   falls back to direct execution if daemon isn't running
3. **Hook calls daemon** — `execFile` → HTTP/socket call, ~10ms instead of ~7s
4. **Dream scheduler** — daemon runs `dream --steps N` periodically in the background
   (no more external cron needed)
5. **Imprint worker** — daemon watches session memory files, auto-imprints when they
   settle (replaces the imprint cron job)

**OTP supervision tree:**
```
wetwared_app
├── wetware_gel_server      (GenServer: gel state, briefing, priming, imprint)
├── wetware_dream_worker    (periodic dream steps)
├── wetware_imprint_watcher (file system watcher for session memory)
├── wetware_api_server      (Cowboy/Bandit HTTP or ranch TCP listener)
└── wetware_cli_compat      (backwards-compatible CLI interface)
```

**Benefits:**
- Bootstrap hook goes from ~7s → ~10ms
- Dream steps run continuously in background (more organic gel evolution)
- Imprinting becomes event-driven (file watch) instead of polled (cron)
- Hot code reloading means gel upgrades without restart
- The BEAM finally gets to do what it's built for: stay running

**Migration path:**
1. Add HTTP/socket API to existing wetware OTP app
2. Add `wetwared` escript entry point (start, stop, status)
3. Update `wetware` CLI to try daemon first, fall back to direct
4. Update OpenClaw hook to use HTTP client instead of execFile
5. Add launchd plist for auto-start on macOS
6. Move dream scheduling into daemon
7. Move imprint cron into daemon file watcher

**Launchd plist** (`~/Library/LaunchAgents/com.wetware.daemon.plist`):
```xml
<plist version="1.0">
<dict>
  <key>Label</key><string>com.wetware.daemon</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/cjw/bin/wetwared</string>
    <string>start</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/Users/cjw/.local/log/wetwared.log</string>
  <key>StandardErrorPath</key><string>/Users/cjw/.local/log/wetwared.err</string>
</dict>
</plist>
```

**Timeline:** After core wetware features stabilize. The escript CLI + 15s timeout
is fine for now — it works, it's just slow.
