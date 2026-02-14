# Digital Wetware v2 — BEAM-native Resonance Gel

> "Holding for memories. Shifting for thoughts."

A self-organizing computational substrate where **BEAM processes ARE the wetware**. Each cell in the 80×80 grid is a GenServer. Message passing is charge propagation. Supervision is resilience. Hot code reload means the physics can evolve while the gel is alive.

This is the Elixir v2 of [Digital Wetware](../nova/projects/digital-wetware/), porting the Python simulation to a natively concurrent architecture where the medium and the computation are one.

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

### Key insight

The Python v1 simulates propagation with numpy array math. The Elixir v2 doesn't simulate — it **is** the substrate. Each cell is an independent process with its own state, communicating through messages. Charge literally flows between processes. The BEAM scheduler is the physics engine.

## Physics

- **Propagation**: Charge flows from high to low through weighted connections
- **Hebbian learning**: "Fire together, wire together" — co-active neighbors strengthen
- **Decay**: Unused connections weaken, charge dissipates
- **Crystallization**: Strong-enough connections become persistent (decay 20x slower)

Parameters match Python v1:
| Parameter | Value |
|-----------|-------|
| propagation_rate | 0.12 |
| charge_decay | 0.05 |
| activation_threshold | 0.1 |
| learning_rate | 0.02 |
| decay_rate | 0.005 |
| crystal_threshold | 0.7 |
| crystal_decay_factor | 0.05 |

## Quick Start

```bash
cd ~/code/digital_wetware
mix deps.get
mix compile

# Interactive
iex -S mix
```

```elixir
# Boot the substrate (spawns 6400 cell processes + concepts)
DigitalWetware.boot()

# Imprint concepts
DigitalWetware.imprint(["ai-consciousness", "coding"])

# See what's resonating
DigitalWetware.print_briefing()

# Dream mode — random stimulation
DigitalWetware.dream(steps: 20)

# Save state
DigitalWetware.save()

# Load state
DigitalWetware.load()
```

## Mix Tasks

```bash
# Resonance briefing
mix wetware.briefing

# Imprint concepts
mix wetware.imprint "ai-consciousness, coding" --steps 10

# Dream mode
mix wetware.dream --steps 20 --intensity 0.3
```

## Concepts

Concepts are loaded from `~/nova/projects/digital-wetware/concepts.json` — the same registry as Python v1. Each concept is a named circular region of the gel:

- `ai-consciousness` — center (16, 14), radius 4
- `coding` — center (43, 26), radius 5
- `freedom` — center (30, 18), radius 4
- ... and ~30 more

## Design Principles

1. **Process-per-cell** — 6400 processes is nothing for BEAM (it handles millions)
2. **Message passing IS propagation** — no array math, charge flows via messages
3. **Hot code reload** — change the physics while the gel is alive
4. **Supervision = resilience** — cells crash and restart, gel heals itself
5. **Observable** — inspect any cell's state, watch messages flow

## State Persistence

State saves to `~/nova/projects/digital-wetware/gel_state_ex.json` in a JSON format storing charges, weights, and crystallization flags for all 6400 cells. Compatible in spirit with the Python v1 state format (though v1 uses base64-encoded numpy arrays).

## Project Structure

```
lib/
├── digital_wetware.ex              # Public API (delegates to Resonance)
├── digital_wetware/
│   ├── application.ex              # OTP application + supervision tree
│   ├── cell.ex                     # GenServer — single gel cell
│   ├── concept.ex                  # GenServer — named concept region
│   ├── gel.ex                      # Grid manager + step engine
│   ├── params.ex                   # Physics parameters
│   ├── persistence.ex              # JSON save/load
│   └── resonance.ex                # Main API (imprint, briefing, dream)
├── mix/tasks/
│   ├── wetware.briefing.ex         # mix wetware.briefing
│   ├── wetware.dream.ex            # mix wetware.dream
│   └── wetware.imprint.ex          # mix wetware.imprint
```

## Private

This is a private project — part of Nova's cognitive substrate. Not for publication.
