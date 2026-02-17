# Wetware v1: Sparse Living Gel — Implementation Plan

> Session handoff document. Contains full context for continuing this work.

## Vision

Replace the fixed 80×80 grid with a **sparse, dynamically growing single-substrate gel**. Concepts spawn their own regions, the gel grows as needed, and long-range axons form between frequently co-activated concepts. The substrate is alive — it grows, shrinks, and reshapes around what matters.

## Why This Architecture

We evaluated five topology options:

| Option | Verdict | Why |
|--------|---------|-----|
| Fixed 2D grid (current) | ❌ Ship-blocking | Packing limit ~60-80 concepts. Manual placement. Can't grow. |
| 3D grid | ❌ Deferred | Same limitations at larger scale. Harder to visualize. |
| Pure graph | ❌ Rejected | Loses spatial emergence — interference, gradients, crystallization. Becomes a weighted graph DB. |
| Graph of local gels | ❌ Rejected | Local gels too small for real emergence. Breaks the single-substrate insight. |
| **Sparse living gel** | ✅ **v1 target** | Preserves single-substrate emergence. Scales via sparsity. Grows organically. |

**The core insight we're protecting:** emergence happens in the *spaces between* concepts, not just inside them. A single continuous substrate allows interference, gradient fields, and unexpected crystallization patterns that no graph topology can replicate.

## Key Decisions & Tradeoffs

### 1. Sparse cells (on-demand) vs. dense grid

**Decision:** Cells exist only where needed. Empty space has no processes.

**Why:** The current 80×80 boots 6,400 processes regardless of how many concepts exist. A sparse gel with 50 concepts might only need ~1,000-4,000 live cells. With 200 concepts, ~6,000-18,000. BEAM handles this fine, and we're not paying for void.

**Tradeoff:** Propagation into empty space requires a spawn decision. We gate this with a `spawn_threshold` — charge accumulates in an ETS pending-input table, and a cell only spawns when enough charge has pooled. This prevents flood-spawning from a single strong stimulus.

### 2. Unbounded coordinates vs. fixed grid

**Decision:** No fixed width/height. Coordinates are arbitrary `{integer, integer}` pairs. The gel grows outward as concepts are added.

**Why:** Fixed grids create artificial packing constraints. With 35 concepts on 80×80, we're already tight. An agent with 200+ concepts simply can't fit. Unbounded coordinates mean the layout engine always has room.

**Tradeoff:** Visualization needs a dynamic viewport. You can't assume a fixed canvas. The `bounds()` function reports the current extent of the gel for rendering.

### 3. Axons (physical long-range connections) vs. association weights only

**Decision:** Both. Associations remain as lightweight semantic links. Axons form as physical cell chains when the association is strong AND the concepts are distant AND they're repeatedly co-fired.

**Why:** Association weights are fast and cheap — they answer "are these concepts related?" But they don't participate in the gel physics. An axon is a chain of real cells connecting two distant concept regions. Charge flows through it. Other axons can interfere with it at crossing points. It can crystallize (persist) or decay (dissolve). This is the "white matter" of the substrate.

**Tradeoff:** Axons are expensive (many cells per connection). The formation trigger is deliberately conservative — you earn an axon through sustained co-activation, not a single co-occurrence. We expect most concept pairs to stay as association-weight-only; only the truly important long-range connections get axons.

### 4. Cell types (concept / axon / interstitial)

**Decision:** Cells have a `kind` field that determines their physics.

| Kind | Spawned by | Behavior |
|------|-----------|----------|
| `:concept` | Concept seeding | High charge retention, Hebbian learning, can crystallize. The "gray matter." |
| `:axon` | Axon formation | Fast propagation, lower decay, connects distant regions. The "white matter." |
| `:interstitial` | Overflow propagation | Weak, decays quickly. Exists temporarily when charge spills beyond concept boundaries. |

**Why:** Different regions of the substrate should behave differently, just like different tissue types in a brain. A concept's core cells should be sticky and persistent. An axon should conduct quickly. Interstitial space should be ephemeral.

**Tradeoff:** More complexity in the Cell GenServer (branching on `kind`). But this is where we get the extensibility CJ asked about — someone could add new cell types (`:emotional`, `:temporal`) with custom physics.

### 5. Dynamic concept regions (grow/shrink) vs. fixed radius

**Decision:** Concept radius is dynamic. Grows with usage, shrinks with dormancy.

**Formula:** `target_radius = r_min + floor(k * log1p(usage_ema))`

**Why:** A concept you interact with daily should have more presence in the substrate than one you mentioned once. Growth means more cells, more surface area for interaction with neighbors, more room for internal crystallization patterns. Shrinkage means dormant concepts fade to a minimal footprint, freeing space.

**Tradeoff:** Growth/shrinkage needs hysteresis to avoid oscillation. We use EMA (exponential moving average) for the usage score, not raw counts, so brief spikes don't cause wild swings. Shrinkage only despawns non-crystallized edge cells — anything that's earned crystallization stays.

### 6. Live processes vs. ETS snapshots for dormant cells

**Decision:** Active cells are GenServer processes. Dormant cells are snapshots in ETS (no process). Cells transition between states.

**Why:** An agent with 1,000 concepts might have 80,000 cells in the gel state, but only a fraction are active at any time. Keeping dormant cells as processes wastes scheduler time and memory. ETS snapshots are cheap to store and fast to rehydrate.

**Tradeoff:** Accessing a dormant cell requires spawning it first. We apply "lazy decay on access" — when a dormant cell wakes up, we calculate its decay from `last_step` to `current_step` using closed-form math, so we don't need to step dormant cells individually.

### 7. Layout engine as a behaviour (extensible)

**Decision:** The layout strategy is a pluggable Elixir behaviour.

```elixir
defmodule Wetware.Layout.Strategy do
  @callback place(name :: String.t(), tags :: [String.t()], existing :: map()) :: {integer(), integer()}
  @callback should_grow?(name :: String.t(), usage :: float()) :: boolean()
  @callback should_shrink?(name :: String.t(), dormancy :: integer()) :: boolean()
end
```

**Default:** `Wetware.Layout.Proximity` — places new concepts near existing concepts with overlapping tags. Spiral search outward if crowded.

**Why:** Different agents might want different spatial organization. A research agent might cluster by discipline. A personal agent might cluster by life domain. Someone building something weird might want random scatter or force-directed layout. The behaviour interface makes this pluggable without touching core gel code.

---

## Implementation Phases

### Phase 1: Sparse Grid Foundation
**Goal:** Replace fixed 80×80 with sparse on-demand cells. All existing features still work.

**Changes:**
- `Gel` — remove fixed width/height boot loop. Add `ensure_cell/2`, `bounds/0`. Track cells via ETS index.
- `Cell` — add `kind` field, `last_step`, `last_active_step`. Child spec `restart: :temporary`.
- `Params` — remove `width`/`height`. Add `spawn_threshold`, `despawn_dormancy_ttl`.
- `Application` — swap `DynamicSupervisor` for `PartitionSupervisor`. Add `Gel.Index` (ETS owner), `Gel.Lifecycle` (sweep).
- `Persistence` — save/load sparse cell map instead of dense grid arrays. New format `elixir-v3-sparse`.
- `Concept` — seeding spawns cells in region via `ensure_cell(:concept_seed)`.
- `Layout` — implement `Layout.Engine` GenServer + `Layout.Proximity` strategy.

**Tests:** Boot with 0 cells → add concept → cells spawn → imprint → charge propagates → briefing works → save/load round-trip.

**Migration:** Provide a one-time migration script that converts `elixir-v2` dense state to `elixir-v3-sparse` format.

### Phase 2: Dynamic Regions
**Goal:** Concepts grow and shrink based on usage.

**Changes:**
- `ConceptRegion` — new module. Tracks usage EMA per concept. Computes target radius. `grow_step/1` spawns perimeter cells. `shrink_step/1` marks edge cells for despawn.
- `Gel.Lifecycle` — integrate shrink sweeps. Despawn cells below charge threshold with no crystallization.
- `Gel.Stepper` — replace full-grid `step()` with active-frontier stepping. Track active set in ETS queue. Lazy decay for dormant cells on access.

**Tests:** Stimulate concept repeatedly → radius grows. Stop stimulating → radius shrinks. Two growing concepts meet → border cells have multiple owners.

### Phase 3: Long-Range Axons
**Goal:** Physical pathways form between frequently co-activated distant concepts.

**Changes:**
- `Axon.Planner` — GenServer that observes co-activations. Maintains sliding window counts. Triggers axon formation when conditions met.
- `Axon.Store` — ETS table for axon metadata (endpoints, path, strength, state).
- `Axon` route computation — A* on unbounded lattice. Cost function: low through empty, high through concept cores, reward for bundling, penalty for crossing.
- `Cell` — axon cells get `kind: :axon` with different physics (faster propagation, lower decay).
- `Gel.Stepper` — axon cells included in active frontier when either endpoint concept is active.

**Tests:** Co-activate two distant concepts repeatedly → axon forms → charge conducts between them → stop co-activating → axon decays → unless crystallized.

### Phase 4: Extension Points & Polish
**Goal:** Clean up for open source. Make it extensible.

**Changes:**
- `Layout.Strategy` behaviour finalized.
- Cell type system documented (how to add custom cell types).
- `wetware init` command — accepts concept list, runs layout engine, scaffolds data dir.
- `wetware viz` — basic terminal or HTML visualization of sparse gel state.
- `wetware migrate` — converts v2 state to v3.
- README updated for new architecture.
- Example integration guide (OpenClaw, generic agent).

---

## Concept Schema (New)

**concepts.json** (user-facing, catalog only):
```json
{
  "concepts": {
    "coding": { "tags": ["programming", "software", "engineering"] },
    "music": { "tags": ["sound", "art", "composition"] }
  }
}
```

No positions. No radii. Just names and tags.

**gel_state.json** (machine-managed, includes placement):
```json
{
  "version": "elixir-v3-sparse",
  "step_count": 1834,
  "concepts": {
    "coding": {
      "center": [43, 26],
      "base_radius": 3,
      "current_radius": 5,
      "usage_ema": 0.72,
      "created_step": 12,
      "tags": ["programming", "software", "engineering"]
    }
  },
  "cells": {
    "43:26": { "charge": 0.45, "kind": "concept", "owners": ["coding"], "last_step": 1834 },
    "44:26": { "charge": 0.38, "kind": "concept", "owners": ["coding"], "last_step": 1834 }
  },
  "axons": {
    "coding<>music": {
      "endpoints": ["coding", "music"],
      "path": [[43,27],[43,28],[44,29],[45,30]],
      "strength": 0.65,
      "state": "plastic",
      "last_used_step": 1820
    }
  },
  "associations": {
    "coding|music": 0.42,
    "coding|planning": 0.78
  }
}
```

---

## Supervision Tree (New)

```
Wetware.Application
├── Registry (CellRegistry, partitioned)
├── Registry (ConceptRegistry)
├── PartitionSupervisor (CellSupers → DynamicSupervisors for cells)
├── Wetware.Gel.Index          # ETS owner: coord→snapshot, pending input, bounds
├── Wetware.Gel.Stepper        # Active-frontier stepping loop
├── Wetware.Gel.Lifecycle      # Periodic dormancy sweeps + despawn
├── Wetware.Layout.Engine      # Concept placement
├── Wetware.Axon.Planner       # Co-activation observer + axon formation
├── Wetware.Axon.Store         # ETS owner for axon metadata
├── Wetware.Associations       # Concept-level co-activation weights
├── DynamicSupervisor (ConceptSupervisor)
│   ├── Concept "coding"
│   ├── Concept "music"
│   └── ...
└── Wetware.Gel (coordinator GenServer)
```

---

## BEAM-Specific Notes

1. **Cell child spec:** `restart: :temporary` — intentional despawn shouldn't trigger restart.
2. **Registry partitioning:** Use `System.schedulers_online() * 4` partitions for CellRegistry to reduce contention.
3. **ETS for hot paths:** Coord→PID lookup, pending input accumulation, active set tracking all go through ETS, not GenServer calls.
4. **Bounded stepping:** Use `Task.async_stream` with `max_concurrency` to avoid task explosion during step.
5. **Mailbox protection:** Epoch tags on step messages — cells ignore stale epochs.
6. **Hysteresis on spawn/despawn:** Minimum lifetime before despawn eligible. Prevents churn.

---

## Process Count Estimates

| Concepts | Estimated live cells | Total processes |
|----------|---------------------|-----------------|
| 50 | 1,000 – 4,000 | ~1,100 – 4,100 |
| 200 | 6,000 – 18,000 | ~6,300 – 18,300 |
| 1,000 | 25,000 – 80,000 | ~26,100 – 81,200 |

Depends on active frontier + axon density, not concept count alone. BEAM handles all ranges comfortably.

---

## Files to Change

| File | Phase | What |
|------|-------|------|
| `lib/wetware/gel.ex` | 1 | Sparse grid, ensure_cell, bounds, remove fixed boot |
| `lib/wetware/cell.ex` | 1 | Add kind, last_step, temporary restart |
| `lib/wetware/params.ex` | 1 | Remove width/height, add sparse params |
| `lib/wetware/application.ex` | 1 | New supervision tree |
| `lib/wetware/persistence.ex` | 1 | Sparse format v3 |
| `lib/wetware/concept.ex` | 1 | Seed via ensure_cell, drop cx/cy/r from struct |
| `lib/wetware/layout.ex` | 1 | Rewrite as Engine + Proximity strategy |
| `lib/wetware/gel/index.ex` | 1 | NEW — ETS owner for coord index |
| `lib/wetware/gel/stepper.ex` | 2 | NEW — active-frontier stepping |
| `lib/wetware/gel/lifecycle.ex` | 2 | NEW — dormancy sweeps |
| `lib/wetware/concept_region.ex` | 2 | NEW — dynamic grow/shrink |
| `lib/wetware/axon/planner.ex` | 3 | NEW — co-activation observer |
| `lib/wetware/axon/store.ex` | 3 | NEW — axon metadata |
| `lib/wetware/axon/router.ex` | 3 | NEW — A* pathfinding |
| `lib/wetware/cli.ex` | 1-4 | Update for new commands |
| `lib/wetware/resonance.ex` | 1-2 | Update boot/imprint/briefing for sparse |
| `lib/wetware/discovery.ex` | 1 | Already built, minor updates |
| `lib/wetware/pruning.ex` | 2 | Integrate with lifecycle |

---

## Open Questions (Decide During Implementation)

1. **Axon routing: A* vs. simpler straight-line with jitter?** A* is more realistic but complex. Straight-line with noise might be good enough for v1.
2. **Should interstitial cells ever crystallize?** If charge repeatedly spills into the same interstitial region, should it eventually become permanent? (This would be emergent concept formation at the substrate level — very cool but possibly chaotic.)
3. **Multi-owner border cells:** When two concepts grow into each other, border cells get both owners. How does stimulating one concept affect the other through shared cells? Direct charge transfer? Weighted by ownership proportion?
4. **Concept merging:** If two concepts grow so close they substantially overlap, should they merge? Or is overlap the desired behavior (concepts that are deeply entangled)?
5. **Hot code reload for physics:** Can we actually change cell physics while the gel is alive? The BEAM supports it, but we need to design for it (params as runtime config, not compile-time).

---

## How to Start the Next Session

1. Read this document
2. Read current source: `lib/wetware/*.ex` (the codebase as of session end)
3. Read `docs/ARCHITECTURE.md` for the lifecycle diagrams
4. Start with **Phase 1** — the sparse grid foundation
5. Run `mix test` to confirm current 26 tests pass before changing anything
6. Build incrementally: each phase should leave tests green

The existing tests assume a fixed 80×80 grid, so they'll need updating in Phase 1. Write new sparse-aware tests alongside the refactor.
