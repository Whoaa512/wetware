---
name: wetware-memory
description: Give your agent a subconscious — orientation and disposition via Wetware.
metadata:
  {
    "openclaw":
      {
        "emoji": "🧬",
        "skillKey": "wetware-memory",
        "requires": { "bins": ["wetware"] },
      },
  }
---

# Wetware Memory

Wetware gives your agent a sense of *what's alive right now* — not retrieval, but disposition.

## The Loop

Run this cycle naturally as part of your agent workflow:

### 1. Orient (before tasks)

```bash
wetware briefing
```

Read the output. It tells you what concepts are active, warm, and fading. Use this as context for how you approach the next task — not as facts to recall, but as orientation.

### 2. Imprint (after tasks)

```bash
wetware imprint "concepts,from,what,you,just,did" --steps 5
```

Pick 2-5 concepts that capture what was meaningful. Use stable, reusable names. The gel will strengthen connections between co-activated concepts automatically.

### 3. Dream (during idle time)

```bash
wetware dream --steps 10
```

Random stimulation lets the substrate find connections you didn't make explicitly. Run this during heartbeats or quiet periods.

## Auto-Imprint (after conversations)

For richer imprinting from full conversations:

```bash
wetware auto-imprint "summary or transcript text" --duration_minutes 30 --depth 7
```

Depth 1-10. Longer/deeper sessions should imprint more strongly.

## Heartbeat Integration

Add to your heartbeat routine:

```bash
# Get a briefing and dream a few steps
wetware briefing
wetware dream --steps 5
```

The briefing output tells you what's resonating. If something surprising is active, it might be worth mentioning to your human.

## Commands

| Command | What it does |
|---------|-------------|
| `wetware briefing` | Show what's resonating right now |
| `wetware imprint "a,b,c"` | Strengthen concepts from recent work |
| `wetware dream --steps N` | Random stimulation, find new connections |
| `wetware auto-imprint "text"` | Extract and imprint from conversation text |
| `wetware priming` | Generate disposition hints for system prompts |
| `wetware status` | Gel state summary |
| `wetware viz` | Open browser visualization |

## Tips

- **Concept names should be stable.** Use `coding` not `wrote-python-script`. The gel tracks *themes*, not events.
- **Don't over-imprint.** 2-5 concepts per session is plenty. The gel does the rest.
- **Trust the dream.** Unexpected activations often surface real connections.
- **Briefing ≠ todo list.** It's a mirror of where your attention has been, not where it should go.
