defmodule Wetware.Resonance do
  @moduledoc """
  The main API for the digital wetware.

  This is what you interact with - imprint concepts, get briefings,
  run dream mode, save and load state.
  """

  alias Wetware.{Concept, DataPaths, Gel, Persistence}

  @dormancy_table :wetware_dormancy

  @doc """
  Boot the gel substrate and load concepts.
  Call this once to bring the wetware online.
  """
  def boot(opts \\ []) do
    DataPaths.ensure_data_dir!()
    concepts_path = Keyword.get(opts, :concepts_path, DataPaths.concepts_path())
    ensure_concepts_file!(concepts_path)

    case Gel.boot() do
      :ok -> :ok
      {:ok, :already_booted} -> :ok
    end

    case Concept.load_from_json(concepts_path) do
      concepts when is_list(concepts) ->
        register_missing_concepts(concepts)
        ensure_dormancy_table!()
        seed_dormancy_for_all()
        :ok

      {:error, reason} ->
        IO.puts("Could not load concepts: #{inspect(reason)}")
        :ok
    end
  end

  @doc "Add a concept at runtime and persist to concepts.json."
  def add_concept(concept_or_attrs, opts \\ [])

  def add_concept(%Concept{} = concept, opts) do
    concepts_path = Keyword.get(opts, :concepts_path, DataPaths.concepts_path())

    with :ok <- ensure_concepts_file!(concepts_path),
         :ok <- ensure_name_available(concept.name),
         :ok <- Concept.register_all([concept]),
         :ok <- persist_concept(concept, concepts_path) do
      ensure_dormancy_table!()
      :ets.insert(@dormancy_table, {concept.name, Gel.step_count()})
      {:ok, concept}
    end
  end

  def add_concept(attrs, opts) when is_map(attrs) do
    concept = %Concept{
      name: Map.fetch!(attrs, :name),
      cx: Map.fetch!(attrs, :cx),
      cy: Map.fetch!(attrs, :cy),
      r: Map.get(attrs, :r, 3),
      tags: Map.get(attrs, :tags, [])
    }

    add_concept(concept, opts)
  end

  @doc "Remove a concept at runtime and persist concepts.json."
  def remove_concept(name, opts \\ []) when is_binary(name) do
    concepts_path = Keyword.get(opts, :concepts_path, DataPaths.concepts_path())

    case Registry.lookup(Wetware.ConceptRegistry, name) do
      [{pid, _}] ->
        :ok = DynamicSupervisor.terminate_child(Wetware.ConceptSupervisor, pid)
        remove_persisted_concept(name, concepts_path)
        ensure_dormancy_table!()
        :ets.delete(@dormancy_table, name)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Imprint concepts - stimulate them and run propagation steps.
  """
  def imprint(concept_names, opts \\ []) do
    steps = Keyword.get(opts, :steps, 5)
    strength = Keyword.get(opts, :strength, 1.0)

    Enum.each(concept_names, fn name ->
      Concept.stimulate(name, strength)
    end)

    Enum.each(1..steps, fn _i ->
      Gel.step()
    end)

    :ok
  end

  @doc "Get a resonance briefing - what's active, warm, dormant."
  def briefing do
    concepts = Concept.list_all()

    concept_states =
      Enum.map(concepts, fn name ->
        charge = Concept.charge(name)
        info = Concept.info(name)
        {name, %{charge: charge, tags: info.tags, cx: info.cx, cy: info.cy, r: info.r}}
      end)
      |> Enum.sort_by(fn {_name, %{charge: c}} -> -c end)

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

    %{
      step_count: Gel.step_count(),
      total_concepts: length(concepts),
      active: active,
      warm: warm,
      dormant: dormant
    }
  end

  @doc "Dream mode - random low-level stimulation to see what resonates."
  def dream(opts \\ []) do
    steps = Keyword.get(opts, :steps, 20)
    intensity = Keyword.get(opts, :intensity, 0.3)
    p = Gel.params()

    before_charges =
      Concept.list_all()
      |> Enum.map(fn name -> {name, Concept.charge(name)} end)
      |> Map.new()

    Enum.each(1..steps, fn _i ->
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

    %{steps: steps, echoes: echoes}
  end

  @doc "Save the current gel state."
  def save(path \\ nil) do
    Persistence.save(path || DataPaths.gel_state_path())
  end

  @doc "Load gel state from file."
  def load(path \\ nil) do
    Persistence.load(path || DataPaths.gel_state_path())
  end

  @doc "List concepts with current charge levels."
  def concepts_with_charges do
    Concept.list_all()
    |> Enum.map(fn name ->
      info = Concept.info(name)

      %{
        name: name,
        charge: Concept.charge(name),
        cx: info.cx,
        cy: info.cy,
        r: info.r,
        tags: info.tags
      }
    end)
    |> Enum.sort_by(&(-&1.charge))
  end

  @doc "Return dormancy info for a concept."
  def dormancy(name, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.05)
    ensure_dormancy_table!()

    current_step = Gel.step_count()
    charge = Concept.charge(name)

    if charge > threshold do
      :ets.insert(@dormancy_table, {name, current_step})
    end

    last_active_step =
      case :ets.lookup(@dormancy_table, name) do
        [{^name, step}] -> step
        [] -> 0
      end

    %{
      concept: name,
      current_step: current_step,
      threshold: threshold,
      last_active_step: last_active_step,
      dormant_steps: max(current_step - last_active_step, 0),
      charge: Float.round(charge, 6)
    }
  end

  @doc "Called by Gel after each step to keep dormancy state current."
  def observe_step(step_count, threshold \\ 0.05) do
    ensure_dormancy_table!()

    Concept.list_all()
    |> Enum.each(fn name ->
      if Concept.charge(name) > threshold do
        :ets.insert(@dormancy_table, {name, step_count})
      else
        maybe_seed_dormancy(name, step_count)
      end
    end)

    :ok
  end

  @doc "Print a formatted briefing to stdout."
  def print_briefing do
    b = briefing()

    IO.puts("")
    IO.puts("===========================================")
    IO.puts("  Wetware - Resonance Briefing")
    IO.puts("===========================================")
    IO.puts("  Step: #{b.step_count}  |  Concepts: #{b.total_concepts}")
    IO.puts("")

    if b.active != [] do
      IO.puts("  ACTIVE:")

      Enum.each(b.active, fn {name, charge} ->
        bar = String.duplicate("#", trunc(charge * 40))
        IO.puts("    #{String.pad_trailing(name, 25)} #{bar} #{charge}")
      end)

      IO.puts("")
    end

    if b.warm != [] do
      IO.puts("  WARM:")

      Enum.each(b.warm, fn {name, charge} ->
        IO.puts("    #{String.pad_trailing(name, 25)} #{charge}")
      end)

      IO.puts("")
    end

    IO.puts("  DORMANT: #{length(b.dormant)} concepts")
    IO.puts("===========================================")
    IO.puts("")
  end

  def concepts_path, do: DataPaths.concepts_path()

  defp ensure_dormancy_table! do
    case :ets.whereis(@dormancy_table) do
      :undefined ->
        :ets.new(@dormancy_table, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        :ok
    end

    :ok
  end

  defp seed_dormancy_for_all do
    step = Gel.step_count()

    Concept.list_all()
    |> Enum.each(fn name -> maybe_seed_dormancy(name, step) end)
  end

  defp maybe_seed_dormancy(name, step) do
    case :ets.lookup(@dormancy_table, name) do
      [] -> :ets.insert(@dormancy_table, {name, step})
      _ -> :ok
    end
  end

  defp ensure_name_available(name) do
    if name in Concept.list_all() do
      {:error, :already_exists}
    else
      :ok
    end
  end

  defp register_missing_concepts(concepts) do
    existing = MapSet.new(Concept.list_all())
    missing = Enum.reject(concepts, fn c -> MapSet.member?(existing, c.name) end)

    if missing == [] do
      :ok
    else
      Concept.register_all(missing)
    end
  end

  defp ensure_concepts_file!(path) do
    File.mkdir_p!(Path.dirname(path))

    if File.exists?(path) do
      :ok
    else
      File.write!(path, Jason.encode!(%{"concepts" => %{}}, pretty: true))
      :ok
    end
  end

  defp persist_concept(%Concept{} = concept, concepts_path) do
    with {:ok, data} <- File.read(concepts_path),
         {:ok, decoded} <- Jason.decode(data) do
      concepts = Map.get(decoded, "concepts", %{})

      updated =
        Map.put(concepts, concept.name, %{
          "cx" => concept.cx,
          "cy" => concept.cy,
          "r" => concept.r,
          "tags" => concept.tags
        })

      File.write!(
        concepts_path,
        Jason.encode!(Map.put(decoded, "concepts", updated), pretty: true)
      )

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp remove_persisted_concept(name, concepts_path) do
    with {:ok, data} <- File.read(concepts_path),
         {:ok, decoded} <- Jason.decode(data) do
      concepts = Map.get(decoded, "concepts", %{})
      updated = Map.delete(concepts, name)

      File.write!(
        concepts_path,
        Jason.encode!(Map.put(decoded, "concepts", updated), pretty: true)
      )

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
