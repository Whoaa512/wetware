# Disposition Hints Format

`wetware briefing` now includes a transparent `disposition_hints` field.

## Schema

Each hint is a map:

```json
{
  "id": "lean_gentle",
  "orientation": "lean_toward_gentleness",
  "prompt_hint": "Favor gentleness, listening, and de-escalation in tone.",
  "confidence": 0.72,
  "sources": [
    { "concept": "care", "charge": 0.81 },
    { "concept": "conflict", "charge": 0.63 }
  ],
  "override_key": "gentleness"
}
```

## Consumption Rules

1. Treat hints as suggestions, not hard constraints.
2. Surface hints to both agent and human operator.
3. Allow explicit overrides by `override_key`.
4. Ignore hints with low confidence (`< 0.2`) unless explicitly enabled.

## Current Built-in Hints

- `lean_gentle`: triggers when both kindness-like and conflict-like concepts are warm.
- `be_concise`: triggers when overload-like concepts are warm.

The format is intentionally stable so additional hints can be added without breaking integrations.
