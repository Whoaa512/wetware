# AGENTS.md — Wetware

## Project

BEAM-native resonance gel for AI agent memory. Elixir/OTP. See ROADMAP.md for full context.

## Stack

- **Language:** Elixir (OTP/BEAM)
- **Build:** Mix
- **Tests:** `mix test`
- **CLI:** `./wetware` (escript)

## Coding Style

- Elixir conventions, `mix format` before committing
- GenServer-per-cell architecture — respect the process model
- Tests go in `test/` mirroring `lib/` structure
- Keep modules small and focused

## Asana Task Loop

This project uses Asana for task management. The `asana` CLI is available.

### Setup

The repo has `.asana.json` with the project context. The CLI reads it automatically.

### Autonomous Work Loop

When told to "work on tasks", "do the next task", or similar:

1. **Find work:** `asana task list --completed false --limit 5`
2. **Pick the top unblocked task** (check descriptions for "blocked by" references)
3. **Start a session:** `asana session start --task <gid>`
4. **Do the work.** Log meaningful progress:
   - `asana log "Implemented X"`
   - `asana log --type decision "Chose Y because Z"`
   - `asana log --type blocker "Need clarification on X"` (then stop and report)
5. **Run tests:** `mix test` — don't mark done if tests fail
6. **End session:** `asana session end --summary "What was done"`
7. **Mark complete:** `asana done`
8. **Commit:** `git add -A && git commit -m "descriptive message"`
9. **Loop:** Go back to step 1. Stop when no tasks remain or you hit a blocker.

### Rules

- **Never skip tests.** If tests fail, fix them before moving on.
- **Log decisions.** Future sessions will read your comments.
- **Stop on blockers.** Don't guess — log the blocker and report it.
- **One task at a time.** Finish or explicitly block before moving to next.
- **Create subtasks** if a task is too large: `asana task create --name "subtask" --parent <gid>`
- **If you discover new work**, create a task: `asana task create --name "description"`

## Testing

```bash
mix test                    # Run all tests
mix test test/specific_test.exs  # Run specific test
mix test --trace            # Verbose output
```

## Key Architecture

- `lib/wetware/gel.ex` — The resonance gel (main GenServer)
- `lib/wetware/cell.ex` — Individual cell processes
- `lib/wetware/concept.ex` — Concept definitions and regions
- `lib/wetware/cli.ex` — CLI entry point
- `wetware` — Escript binary

## Don't

- Don't change the gel physics without understanding the math (see docs/)
- Don't add framework dependencies — this is framework-agnostic by design
- Don't hardcode paths — everything configurable via `~/.config/wetware/`
