defmodule DigitalWetware do
  @moduledoc """
  Digital Wetware — A BEAM-native resonance gel substrate.

  Each cell is a process. Message passing is propagation.
  Supervision is resilience. The BEAM IS the wetware.

  ## Quick Start

      # Boot the substrate
      DigitalWetware.boot()

      # Imprint some concepts
      DigitalWetware.imprint(["ai-consciousness", "coding"])

      # Check what's resonating
      DigitalWetware.briefing()

      # Dream mode
      DigitalWetware.dream(steps: 20)

      # Save state
      DigitalWetware.save()
  """

  defdelegate boot(opts \\ []), to: DigitalWetware.Resonance
  defdelegate imprint(concepts, opts \\ []), to: DigitalWetware.Resonance
  defdelegate briefing(), to: DigitalWetware.Resonance
  defdelegate print_briefing(), to: DigitalWetware.Resonance
  defdelegate dream(opts \\ []), to: DigitalWetware.Resonance
  defdelegate save(path \\ nil), to: DigitalWetware.Resonance
  defdelegate load(path \\ nil), to: DigitalWetware.Resonance
end
