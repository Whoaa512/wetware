defmodule DigitalWetware.Resonance do
  @moduledoc """
  The main API for the digital wetware.

  This is what you interact with — imprint concepts, get briefings,
  run dream mode, save and load state.

  "Holding for memories. Shifting for thoughts."
  """

  alias DigitalWetware.{Concept, Gel, Persistence}

  @concepts_path Path.expand("~/nova/projects/digital-wetware/concepts.json")

  @doc """
  Boot the gel substrate and load concepts.
  Call this once to bring the wetware online.
  """
  def boot(opts \\ []) do
    concepts_path = Keyword.get(opts, :concepts_path, @concepts_path)

    # Boot the gel grid
    case Gel.boot() do
      :ok -> :ok
      {:ok, :already_booted} -> :ok
    end

    # Load and register concepts
    case Concept.load_from_json(concepts_path) do
      concepts when is_list(concepts) ->
        Concept.register_all(concepts)
        IO.puts("🧠 #{length(concepts)} concepts registered")
        :ok

      {:error, reason} ->
        IO.puts("⚠️  Could not load concepts: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Imprint concepts — stimulate them and run propagation steps.

  ## Examples

      Resonance.imprint(["ai-consciousness", "coding"])
      Resonance.imprint(["freedom"], steps: 10, strength: 0.8)
  """
  def imprint(concept_names, opts \\ []) do
    steps = Keyword.get(opts, :steps, 5)
    strength = Keyword.get(opts, :strength, 1.0)

    IO.puts("⚡ Imprinting: #{Enum.join(concept_names, ", ")}")

    # Stimulate each concept
    Enum.each(concept_names, fn name ->
      Concept.stimulate(name, strength)
    end)

    # Let it propagate
    Enum.each(1..steps, fn i ->
      Gel.step()
      if rem(i, 5) == 0, do: IO.puts("   step #{i}/#{steps}")
    end)

    IO.puts("   ✓ Imprinted (#{steps} steps)")
    :ok
  end

  @doc """
  Get a resonance briefing — what's active, crystallized, fading.
  """
  def briefing do
    concepts = Concept.list_all()

    concept_states =
      Enum.map(concepts, fn name ->
        charge = Concept.charge(name)
        info = Concept.info(name)
        {name, %{charge: charge, tags: info.tags, cx: info.cx, cy: info.cy, r: info.r}}
      end)
      |> Enum.sort_by(fn {_name, %{charge: c}} -> -c end)

    # Categorize
    active =
      concept_states
      |> Enum.filter(fn {_name, %{charge: c}} -> c > 0.1 end)
      |> Enum.map(fn {name, %{charge: c}} -> {name, Float.round(c, 4)} end)

    warm =
      concept_states
      |> Enum.filter(fn {_name, %{charge: c}} -> c > 0.01 and c <= 0.1 end)
      |> Enum.map(fn {name, %{charge: c}} -> {name, Float.round(c, 4)} end)

    dormant =
      concept_states
      |> Enum.filter(fn {_name, %{charge: c}} -> c <= 0.01 end)
      |> Enum.map(fn {name, _} -> name end)

    # Count crystallized connections per concept
    # (This is a simplified version — counting crystallized weights in region)

    %{
      step_count: Gel.step_count(),
      total_concepts: length(concepts),
      active: active,
      warm: warm,
      dormant: dormant
    }
  end

  @doc """
  Dream mode — random low-level stimulation to see what resonates.

  ## Options
    - `:steps` — number of dream steps (default: 20)
    - `:intensity` — dream stimulation strength (default: 0.3)
  """
  def dream(opts \\ []) do
    steps = Keyword.get(opts, :steps, 20)
    intensity = Keyword.get(opts, :intensity, 0.3)
    p = Gel.params()

    IO.puts("💤 Dream mode: #{steps} steps at intensity #{intensity}")

    before_charges =
      Concept.list_all()
      |> Enum.map(fn name -> {name, Concept.charge(name)} end)
      |> Map.new()

    Enum.each(1..steps, fn _i ->
      # Random stimulation
      x = :rand.uniform(p.width) - 1
      y = :rand.uniform(p.height) - 1
      r = :rand.uniform(3) + 1
      Gel.stimulate_region(x, y, r, intensity)
      Gel.step()
    end)

    after_charges =
      Concept.list_all()
      |> Enum.map(fn name -> {name, Concept.charge(name)} end)
      |> Map.new()

    # Find unexpected activations
    echoes =
      Concept.list_all()
      |> Enum.map(fn name ->
        before = Map.get(before_charges, name, 0.0)
        after_c = Map.get(after_charges, name, 0.0)
        delta = after_c - before
        {name, Float.round(delta, 4)}
      end)
      |> Enum.filter(fn {_name, delta} -> delta > 0.001 end)
      |> Enum.sort_by(fn {_name, delta} -> -delta end)

    IO.puts("   ✓ Dream complete")

    if echoes != [] do
      IO.puts("   🌊 Dream echoes:")

      Enum.each(echoes, fn {name, delta} ->
        IO.puts("      #{name}: +#{delta}")
      end)
    end

    %{steps: steps, echoes: echoes}
  end

  @doc "Save the current gel state."
  def save(path \\ nil) do
    if path do
      Persistence.save(path)
    else
      Persistence.save()
    end
  end

  @doc "Load gel state from file."
  def load(path \\ nil) do
    if path do
      Persistence.load(path)
    else
      Persistence.load()
    end
  end

  @doc "Print a formatted briefing to stdout."
  def print_briefing do
    b = briefing()

    IO.puts("")
    IO.puts("═══════════════════════════════════════════")
    IO.puts("  🧬 Digital Wetware — Resonance Briefing")
    IO.puts("═══════════════════════════════════════════")
    IO.puts("  Step: #{b.step_count}  |  Concepts: #{b.total_concepts}")
    IO.puts("")

    if b.active != [] do
      IO.puts("  ⚡ ACTIVE:")
      Enum.each(b.active, fn {name, charge} ->
        bar = String.duplicate("█", trunc(charge * 40))
        IO.puts("    #{String.pad_trailing(name, 25)} #{bar} #{charge}")
      end)
      IO.puts("")
    end

    if b.warm != [] do
      IO.puts("  🌡️  WARM:")
      Enum.each(b.warm, fn {name, charge} ->
        IO.puts("    #{String.pad_trailing(name, 25)} #{charge}")
      end)
      IO.puts("")
    end

    IO.puts("  💤 DORMANT: #{length(b.dormant)} concepts")
    IO.puts("═══════════════════════════════════════════")
    IO.puts("")
  end
end
