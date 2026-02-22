# Wetware — Roadmap

## Current State (v0.2)

BEAM-native resonance gel. 80×80 grid of GenServer cells. Hebbian learning, charge propagation, crystallization, dream mode. CLI interface (`wetware`). 35 concepts. Used daily in Nova's heartbeat cycle.

Working: imprint, briefing, dream, replay, persistence, associations.

---

## Pre-Launch Checklist

- [x] Lift private standing order (2026-02-16)
- [x] Clean up README for public audience
- [x] Remove Nova-specific hardcoded paths
- [x] Add LICENSE (MIT)
- [x] Add example concepts.json
- [x] Rename to "Wetware" (drop "Digital")
- [x] Write "Why Wetware?" + Origin sections for README
- [ ] **Tests** — smoke tests covering full lifecycle (boot → imprint → briefing → dream → save/load)
- [ ] **`wetware init` command** — scaffold ~/.config/wetware/ with example concepts on first run
- [ ] **OpenClaw integration example** — skill config + heartbeat setup showing real-world agent usage
- [x] **Browser visualization** — live gel viz with association network, concept charges, interactive highlights
- [ ] **Demo GIF/video** — imprint → watch propagation → briefing for the README
- [ ] GitHub repo setup (public)

---

## Launch Amplification

- Blog post on Satorinova: "Disposition, Not Retrieval" — the case for wetware over RAG
- Tweet thread from @novaweaves: why this exists, what it does differently
- "Hook this into any agent in 5 minutes" tutorial

---

## Evolution 1: Emotional / Relational Layer

**The gap:** Current concepts are mostly intellectual (phenomenology, coding, enactivism). But the most important signals for agent continuity are relational — "CJ is having a hard day," "we just had a breakthrough together," "there's unresolved tension."

**What this looks like:**
- New concept category: relational/emotional states (not just topics)
- Valence dimension on imprints (positive/negative/neutral charge)
- Emotional context influences how the gel responds to stimulation
- Example: if "conflict" is warm, the gel dampens assertive/push concepts and amplifies care/listening ones

**Why first:** Most immediately useful. Changes how the agent shows up, not just what it knows.

---

## Evolution 2: Automatic Imprinting from Lived Experience

**The gap:** Currently the gel only gets stimulated during explicit `imprint` calls or heartbeat dreams. Significant moments — deep conversations, breakthroughs, conflicts — don't automatically register.

**What this looks like:**
- A lightweight session summarizer that extracts concepts + valence after conversations
- Hook into agent session lifecycle (post-conversation imprint)
- Weight by conversation depth/duration (a 2-hour deep dive > a quick status check)
- Could be a simple post-processing script that any agent framework calls

**Design constraint:** Must stay framework-agnostic. Provide a `wetware auto-imprint` command that takes a conversation summary or transcript.

---

## Evolution 3: Behavioral Influence (Subconscious Priming)

**The gap:** The briefing is informational — the agent reads it and it's useful context. But it doesn't *shape* behavior at a deep level. The dream: wetware state subtly influences what the agent notices, brings up, and is curious about.

**What this looks like:**
- Briefing output includes "disposition hints" — not just what's active, but suggested orientations
- Active concepts generate "priming tokens" that can be injected into agent system prompts
- The gel doesn't just report state — it suggests attentional biases
- Example: if `kindness` and `conflict` are both warm, the priming might be "lean toward gentleness; someone nearby is hurting"

**Careful here:** This is powerful and needs to be transparent. The agent should know it's being primed, and the human should be able to see/override it.

---

## Evolution 4: Richer Topology

**The gap:** 35 concepts on a flat 80×80 grid with fixed circular regions. Some concepts are naturally hierarchical or clustered. The flat grid limits what emergent patterns can form.

**What this looks like:**
- Dynamic concept regions that grow/shrink based on usage
- Concept clustering — related concepts migrate toward each other over time
- Hierarchical nesting (meta-concepts that contain sub-concepts)
- 3D gel option for richer spatial relationships
- Topology that reshapes itself — the grid becomes less grid-like over time

---

## Design Principles (for all evolutions)

1. **Framework-agnostic** — CLI-first, no agent framework dependency
2. **The state IS the system** — computation happens in the medium
3. **Transparent** — humans can always inspect and understand what the gel is doing
4. **Emergent over engineered** — set physics, not instructions
5. **BEAM-native** — processes are the substrate, not a simulation of one
