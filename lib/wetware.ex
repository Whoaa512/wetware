defmodule Wetware do
  @moduledoc """
  Wetware — A BEAM-native resonance gel substrate.

  Each cell is a process. Message passing is propagation.
  Supervision is resilience. The BEAM IS the wetware.

  ## Quick Start

      # Boot the substrate
      Wetware.boot()

      # Imprint some concepts
      Wetware.imprint(["ai-consciousness", "coding"])

      # Check what's resonating
      Wetware.briefing()

      # Dream mode
      Wetware.dream(steps: 20)

      # Save state
      Wetware.save()
  """

  defdelegate boot(opts \\ []), to: Wetware.Resonance
  defdelegate imprint(concepts, opts \\ []), to: Wetware.Resonance
  defdelegate briefing(), to: Wetware.Resonance
  defdelegate print_briefing(), to: Wetware.Resonance
  defdelegate dream(opts \\ []), to: Wetware.Resonance
  defdelegate save(path \\ nil), to: Wetware.Resonance
  defdelegate load(path \\ nil), to: Wetware.Resonance
end
