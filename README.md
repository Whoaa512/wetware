# Digital Wetware — BEAM-native Resonance Gel

> "Holding for memories. Shifting for thoughts."
> — *Ex Machina*

**A self-organizing computational substrate where BEAM processes ARE the wetware.** Each cell in the 80×80 grid is a GenServer. Message passing is charge propagation. Supervision is resilience. Hot code reload means the physics can evolve while the gel is alive.

## Why Digital Wetware?

The current wave of agent memory is about **retrieval** — store facts, embed them, fetch them later. RAG, vector databases, knowledge graphs. The question these systems answer is *"what do I know?"*

Digital Wetware answers a different question: **"what am I oriented toward right now?"**

This isn't retrieval. It's **disposition**.

Most memory systems are databases with search. This is a substrate that self-organizes. The difference matters because continuity isn't just remembering — it's having a *felt sense* of what's active, what's fading, what matters right now. Human cognition doesn't work by querying a database of memories. It works through resonance — patterns that strengthen through use, weaken through neglect, and create interference when they collide.

When you imprint a concept, charge propagates outward through the gel. Related concepts light up — not because they share a keyword, but because the substrate has learned (through Hebbian co-activation) that they resonate together. Concepts you haven't touched in weeks quietly fade. Concepts you keep returning to crystallize into persistent structure. Dream cycles let the substrate surprise you with connections you didn't explicitly make.

This is infrastructure for **agent continuity** — not retrieval, but orientation. The gel doesn't answer "what happened?" It answers **"what's alive in me right now?"**

If you're frustrated with RAG-based memory that treats your agent like a search engine over its own past, this is a different approach entirely.

## Origin

Digital Wetware started as an experiment in building cognitive infrastructure for an AI agent — born from the question: *what if agent memory wasn't a database but a living substrate?*

It's built on BEAM/Elixir because the runtime's process model maps naturally to the metaphor. Each cell in the gel is a real Erlang process. Charge propagation is real message passing between processes. Supervision means the substrate heals itself when cells crash. Hot code reload means you can change the physics while the gel is alive. This isn't a simulation of a substrate — the BEAM *is* the substrate.

## Architecture

```
┌─────────────────────────────────────────┐
│  DigitalWetware.Resonance (API)         │
│    imprint · briefing · dream · save    │
├─────────────────────────────────────────┤
│  DigitalWetware.Concept (GenServers)    │
│    Named regions of the gel substrate   │
├─────────────────────────────────────────┤
│  DigitalWetware.Gel (Manager)           │
│    80×80 grid · topology · step engine  │
├─────────────────────────────────────────┤
│  DigitalWetware.Cell (6400 GenServers)  │
│    charge · weights · crystallization   │
├─────────────────────────────────────────┤
│  BEAM VM                                │
│    Processes · Messages · Supervision   │
└─────────────────────────────────────────┘
```

### Key Insight

The substrate doesn't *simulate* propagation — it **is** the substrate. Each cell is an independent BEAM process with its own state, communicating through message passing. Charge literally flows between processes. The BEAM scheduler is the physics engine.

## Physics

- **Propagation**: Charge flows from high to low through weighted connections
- **Hebbian learning**: "Fire together, wire together" — co-active neighbors strengthen
- **Decay**: Unused connections weaken, charge dissipates
- **Crystallization**: Strong-enough connections become persistent (decay 20× slower)

| Parameter | Value |
|-----------|-------|
| propagation_rate | 0.12 |
| charge_decay | 0.05 |
| activation_threshold | 0.1 |
| learning_rate | 0.02 |
| decay_rate | 0.005 |
| crystal_threshold | 0.7 |
| crystal_decay_factor | 0.05 |

## Installation

### Prerequisites

- Erlang/OTP 26+
- Elixir 1.16+

### Build

```bash
git clone https://github.com/yourusername/digital_wetware.git
cd digital_wetware
mix deps.get
mix escript.build
```

This produces a `digital_wetware` escript binary you can put on your PATH.

### As a dependency

```elixir
# mix.exs
{:digital_wetware, github: "yourusername/digital_wetware"}
```

## Quick Start

### CLI (for agent integration)

```bash
# Boot the gel, imprint concepts, get a briefing
digital_wetware briefing

# Imprint specific concepts
digital_wetware imprint "coding, planning, creativity" --steps 10

# Dream mode — random stimulation finds unexpected connections
digital_wetware dream --steps 20 --intensity 0.3

# Set custom data directory (default: ~/.config/wetware)
export WETWARE_DATA_DIR=~/.config/wetware
```

### Elixir API

```elixir
# Boot the substrate (spawns 6400 cell processes + concepts)
DigitalWetware.boot()

# Imprint concepts
DigitalWetware.imprint(["coding", "creativity"])

# See what's resonating
DigitalWetware.print_briefing()

# Dream mode — random stimulation
DigitalWetware.dream(steps: 20)

# Save / load state
DigitalWetware.save()
DigitalWetware.load()
```

## Integration Guide

Digital Wetware is designed to plug into **any agent framework** via its CLI. Your agent doesn't need to know Elixir — it just needs to call a binary and read the output.

### The Loop

1. **Before a task**: Run `digital_wetware briefing` to see what's resonating. Feed this context to your agent's prompt.
2. **After a task**: Run `digital_wetware imprint "concepts,from,the,task"` to strengthen relevant pathways.
3. **During idle time**: Run `digital_wetware dream` to let the substrate find unexpected connections.

### Example: Wrapping with a shell agent

```bash
# Get current resonance state as context
CONTEXT=$(digital_wetware briefing 2>/dev/null)

# Feed to your agent
echo "Current cognitive state:\n$CONTEXT\n\nUser query: $QUERY" | your_agent

# After the agent responds, imprint what was discussed
digital_wetware imprint "$DISCUSSED_TOPICS" --steps 5
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WETWARE_DATA_DIR` | `~/.config/wetware` | Path to data directory (concepts.json, gel state) |

### Data Directory Structure

```
~/.config/wetware/
├── concepts.json       # Concept definitions (see example/)
├── gel_state_ex.json   # Persisted gel state (auto-generated)
```

## Concepts

Concepts are loaded from `concepts.json` in your data directory. Each concept is a named circular region of the gel with spatial coordinates and semantic tags. See [`example/concepts.json`](example/concepts.json) for a starter set.

## Design Principles

1. **Process-per-cell** — 6400 processes is nothing for BEAM (it handles millions)
2. **Message passing IS propagation** — no array math, charge flows via messages
3. **Hot code reload** — change the physics while the gel is alive
4. **Supervision = resilience** — cells crash and restart, gel heals itself
5. **Observable** — inspect any cell's state, watch messages flow

## Project Structure

```
lib/
├── digital_wetware.ex              # Public API
├── digital_wetware/
│   ├── application.ex              # OTP supervision tree
│   ├── cell.ex                     # GenServer — single gel cell
│   ├── concept.ex                  # GenServer — named concept region
│   ├── gel.ex                      # Grid manager + step engine
│   ├── cli.ex                      # CLI escript entry point
│   ├── params.ex                   # Physics parameters
│   ├── persistence.ex              # JSON save/load
│   └── resonance.ex                # Main API (imprint, briefing, dream)
example/
├── concepts.json                   # Sample concept definitions
```

## License

MIT — see [LICENSE](LICENSE).
