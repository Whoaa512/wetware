---
name: wetware-memory
description: Keep agent disposition aligned with active work by briefing/imprinting/dreaming via Wetware CLI.
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

# Wetware Memory Loop

Use this skill when the agent needs durable orientation across tasks.

## Quick Loop

1. Before planning or replying, run `wetware briefing`.
2. Convert active/warm concepts into short context bullets.
3. After completing work, run `wetware imprint "concept1,concept2"` (2-5 concepts).
4. During idle periods, run `wetware dream --steps 10`.

## Command Defaults

- Briefing: `wetware briefing`
- Imprint: `wetware imprint "<comma-separated-concepts>"`
- Dream: `wetware dream --steps 10`
- Status: `wetware status`
- Viz: `wetware viz --port 4157`

## Guardrails

- Never imprint empty concept lists.
- Keep concept names short, stable, and reusable.
- Prefer existing concepts over creating near-duplicates.
- If `wetware` is unavailable, continue without memory actions and report it.
