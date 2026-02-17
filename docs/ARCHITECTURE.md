# Wetware Architecture

## Concept Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                        SEEDING                                  │
│                                                                 │
│  wetware init                                                   │
│    │                                                            │
│    ├─ Interactive: "What matters to you?"                       │
│    │   Agent/human provides seed topics                         │
│    │                                                            │
│    ├─ From file: wetware init --from topics.txt                 │
│    │   One concept per line, with optional tags                 │
│    │                                                            │
│    └─ From conversation: wetware init --from transcript.md      │
│        Extracts concepts from natural language                  │
│                                                                 │
│    ┌──────────────┐                                             │
│    │ Spatial       │  Related concepts placed near each other   │
│    │ Layout Engine │  Uses tag similarity for clustering        │
│    └──────┬───────┘                                             │
│           │                                                     │
│           ▼                                                     │
│    ~/.config/wetware/concepts.json                              │
│    (generated, but human-readable and editable)                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        BOOT                                     │
│                                                                 │
│  wetware boot (or first command auto-boots)                     │
│    │                                                            │
│    ├─ Load concepts.json → Concept structs                      │
│    ├─ Start 6400 Cell GenServers (80×80 grid)                   │
│    ├─ Register Concept GenServers (named regions)               │
│    ├─ Load gel_state.json if exists (restore charges/weights)   │
│    └─ Gel is ONLINE                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ACTIVE LIFECYCLE                             │
│                                                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                   │
│  │ IMPRINT  │    │   STEP   │    │  DREAM   │                   │
│  │          │    │          │    │          │                    │
│  │ External │    │ Charge   │    │ Random   │                    │
│  │ stimulus │───▶│ flows    │    │ stimulus │                    │
│  │ (agent   │    │ between  │◀───│ (idle    │                    │
│  │  calls   │    │ cells    │    │  time)   │                    │
│  │ imprint) │    │          │    │          │                    │
│  └──────────┘    └──────────┘    └──────────┘                   │
│       │               │               │                         │
│       │               ▼               │                         │
│       │     ┌──────────────────┐      │                         │
│       │     │    GEL PHYSICS   │      │                         │
│       │     │                  │      │                         │
│       │     │ • Propagation    │      │                         │
│       │     │ • Hebbian learn  │      │                         │
│       │     │ • Decay          │      │                         │
│       │     │ • Crystallize    │      │                         │
│       │     └──────────────────┘      │                         │
│       │               │               │                         │
│       ▼               ▼               ▼                         │
│  ┌─────────────────────────────────────────┐                    │
│  │              BRIEFING                    │                    │
│  │                                          │                    │
│  │  "What's alive right now?"               │                    │
│  │                                          │                    │
│  │  ⚡ ACTIVE:  concepts with high charge   │                    │
│  │  🌡️ WARM:    recently stimulated         │                    │
│  │  💤 DORMANT: faded, but structure holds  │                    │
│  │                                          │                    │
│  │  + associations between concepts         │                    │
│  │  + emergent clusters                     │                    │
│  └─────────────────────────────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CONCEPT EVOLUTION                              │
│                   (NOT YET IMPLEMENTED)                          │
│                                                                 │
│  ┌─────────────┐                                                │
│  │  DISCOVERY  │  New concepts emerge from repeated             │
│  │             │  unrecognized patterns in imprints              │
│  │  "What keeps│                                                │
│  │  coming up  │  wetware discover --from session.md            │
│  │  that I     │  wetware add "new-concept" --near "coding"     │
│  │  don't have │                                                │
│  │  a name     │  Pending → threshold → graduated to gel        │
│  │  for yet?"  │                                                │
│  └─────────────┘                                                │
│                                                                 │
│  ┌─────────────┐                                                │
│  │   PRUNING   │  Concepts that stay dormant long enough        │
│  │             │  get flagged for removal                       │
│  │  "What's    │                                                │
│  │  dead weight│  wetware prune --dry-run                       │
│  │  I'm        │  wetware prune --confirm                       │
│  │  carrying?" │                                                │
│  │             │  Dormant > N steps → candidate                 │
│  │             │  Crystallized connections preserved             │
│  └─────────────┘                                                │
│                                                                 │
│  ┌─────────────┐                                                │
│  │  MIGRATION  │  Concepts drift toward frequently              │
│  │             │  co-activated neighbors over time               │
│  │  "The map   │                                                │
│  │  reshapes   │  Spatial positions shift gradually              │
│  │  itself"    │  Regions grow/shrink with usage                │
│  └─────────────┘                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PERSISTENCE                                  │
│                                                                 │
│  gel_state.json                                                 │
│    ├─ 6400 cell charges                                         │
│    ├─ Connection weights (per-cell neighbor map)                │
│    ├─ Crystallization flags                                     │
│    ├─ Step count                                                │
│    └─ Associations (concept-to-concept co-activation weights)   │
│                                                                 │
│  concepts.json                                                  │
│    ├─ Concept names, positions (cx, cy), radii, tags            │
│    └─ (Future: pending concepts, pruned history)                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Integration Pattern (Agent-Native)

Wetware is a CLI tool. Any agent framework integrates via shell commands:

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR AGENT                                    │
│                                                                 │
│  On session start:                                              │
│    $ wetware briefing                                           │
│    → Parse output → inject into system prompt / context         │
│                                                                 │
│  After conversations:                                           │
│    $ wetware imprint "concept1, concept2"                       │
│    → Stimulate concepts that were active in the conversation    │
│                                                                 │
│  During idle time:                                              │
│    $ wetware dream --steps 10                                   │
│    → Background processing, let associations form               │
│                                                                 │
│  Periodically:                                                  │
│    $ wetware discover --from recent_sessions/                   │
│    → Find new concepts emerging from usage                      │
│    $ wetware prune --dry-run                                    │
│    → See what's gone dormant enough to consider removing        │
│                                                                 │
│  First-time setup:                                              │
│    $ wetware init                                               │
│    → Interactive or --from file to seed initial concepts        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Design Decisions

### Why a flat grid instead of a graph?
Graphs are great for explicit relationships. But we want **emergent** relationships — structure that forms from use, not from declaration. A spatial grid with local physics gives us:
- Interference patterns (competing concepts create interesting dynamics)
- Gradient fields (charge bleeds between nearby regions)
- Crystallization (stable pathways that resist decay)
- Dreaming (spontaneous pattern replay)

None of these emerge naturally from a graph.

### Why BEAM?
The runtime IS the metaphor. Each cell is a process. Charge propagation is message passing. Supervision is resilience. Hot code reload means the physics can evolve while the gel is alive. We're not simulating a substrate — we're running one.

### Why CLI-first?
Framework-agnosticism. Any agent that can shell out can use wetware. No SDK to import, no protocol to implement, no server to run. Just `wetware briefing` and you're oriented.
