# Emotional/Relational Concept Design (Evolution 1)

## Decision Summary

1. Emotional concepts are **not** a new core type.
2. They are regular concepts with **taxonomy tags**.
3. Mapping to gel regions uses the existing layout engine (tags already influence placement).
4. The starter set lives in a user-editable JSON example file, not hardcoded in code paths.

This keeps the model flexible and avoids locking users into one emotional ontology.

## Why Tags, Not New Type

- Wetware already models concepts with tags.
- A new hardcoded type would force one emotional schema and reduce user control.
- Tags let any concept be emotional, relational, both, or neither.

Recommended tag namespaces:

- `domain:emotional`
- `domain:relational`
- `emotion:<name>` (examples: `emotion:care`, `emotion:tension`)
- `relation:<name>` (examples: `relation:trust`, `relation:repair`)

## Region Mapping

No special placement physics yet.

- Emotional/relational concepts are placed like any other concept.
- Their tags naturally affect proximity through existing layout behavior.
- Later tasks can add valence and bias physics without changing concept schema.

## Starter Set

A starter file is provided at:

- `example/emotional_concepts.json`

It is intentionally editable and minimal. Users can remove, rename, or replace entries.

## Compatibility Notes

- Existing `concepts.json` stays valid.
- No migration required for current users.
- Emotional layer can be adopted incrementally by adding tags to current concepts.
