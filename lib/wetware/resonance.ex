defmodule Wetware.Resonance do
  @moduledoc "Main API for imprinting, dreaming, briefing, and persistence."

  alias Wetware.{Concept, DataPaths, EmotionalBias, Gel, Persistence, Priming, PrimingOverrides}

  @dormancy_table :wetware_dormancy

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

  def add_concept(concept_or_attrs, opts \\ [])

  def add_concept(%Concept{} = concept, opts) do
    concepts_path = Keyword.get(opts, :concepts_path, DataPaths.concepts_path())

    with :ok <- ensure_concepts_file!(concepts_path),
         :ok <- ensure_name_available(concept.name),
         :ok <- Concept.register_all([concept]),
         :ok <- persist_concept(concept, concepts_path) do
      ensure_dormancy_table!()
      :ets.insert(@dormancy_table, {concept.name, Gel.step_count()})
      {:ok, Concept.info(concept.name)}
    end
  end

  def add_concept(attrs, opts) when is_map(attrs) do
    concept = %Concept{
      name: Map.fetch!(attrs, :name),
      cx: Map.get(attrs, :cx),
      cy: Map.get(attrs, :cy),
      r: Map.get(attrs, :r, 3),
      parent: Map.get(attrs, :parent),
      tags: Map.get(attrs, :tags, [])
    }

    add_concept(concept, opts)
  end

  def remove_concept(name, opts \\ []) when is_binary(name) do
    concepts_path = Keyword.get(opts, :concepts_path, DataPaths.concepts_path())

    case Registry.lookup(Wetware.ConceptRegistry, name) do
      [{pid, _}] ->
        :ok = DynamicSupervisor.terminate_child(Wetware.ConceptSupervisor, pid)
        :ok = Gel.unregister_concept(name)
        remove_persisted_concept(name, concepts_path)
        ensure_dormancy_table!()
        :ets.delete(@dormancy_table, name)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  def imprint(concept_names, opts \\ []) do
    steps = Keyword.get(opts, :steps, 5)
    strength = Keyword.get(opts, :strength, 1.0)
    valence = clamp(Keyword.get(opts, :valence, 0.0), -1.0, 1.0)
    Wetware.Associations.co_activate(concept_names)

    Enum.each(concept_names, fn name ->
      effective_strength = strength * EmotionalBias.strength_multiplier(name)
      Concept.stimulate(name, effective_strength, valence: valence)
    end)

    Enum.each(1..steps, fn _ -> Gel.step() end)

    :ok
  end

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

    disposition_hints = Priming.hints(concept_states)

    %{
      step_count: Gel.step_count(),
      total_concepts: length(concepts),
      active: active,
      warm: warm,
      dormant: dormant,
      disposition_hints: disposition_hints
    }
  end

  def dream(opts \\ []) do
    steps = Keyword.get(opts, :steps, 20)
    intensity = Keyword.get(opts, :intensity, 0.3)

    before_charges =
      Concept.list_all()
      |> Enum.map(fn name -> {name, Concept.charge(name)} end)
      |> Map.new()

    b = Gel.bounds()

    Enum.each(1..steps, fn _ ->
      x = rand_between(b.min_x - 2, b.max_x + 2)
      y = rand_between(b.min_y - 2, b.max_y + 2)
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

  def save(path \\ nil), do: Persistence.save(path || DataPaths.gel_state_path())
  def load(path \\ nil), do: Persistence.load(path || DataPaths.gel_state_path())

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

  def priming_payload do
    briefing = briefing()
    disabled_overrides = PrimingOverrides.disabled_keys()

    effective_hints =
      briefing.disposition_hints
      |> Enum.reject(fn hint ->
        key = Map.get(hint, :override_key) || Map.get(hint, "override_key")
        key in disabled_overrides
      end)

    effective_briefing = %{briefing | disposition_hints: effective_hints}
    tokens = Priming.tokens_from_briefing(effective_briefing)
    prompt_block = Priming.prompt_block(effective_briefing)

    %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      tokens: tokens,
      disposition_hints: effective_hints,
      all_disposition_hints: briefing.disposition_hints,
      disabled_overrides: disabled_overrides,
      prompt_block: prompt_block,
      transparent: true,
      override_keys:
        effective_hints
        |> Enum.map(fn hint -> Map.get(hint, :override_key) || Map.get(hint, "override_key") end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  def dormancy(name, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.05)
    ensure_dormancy_table!()

    current_step = Gel.step_count()
    charge = Concept.charge(name)

    if charge > threshold, do: :ets.insert(@dormancy_table, {name, current_step})

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

  def observe_step(step_count, threshold \\ 0.05) do
    ensure_dormancy_table!()

    Concept.list_all()
    |> Enum.each(fn name ->
      charge =
        try do
          Concept.charge(name)
        catch
          :exit, _ -> 0.0
        end

      if charge > threshold,
        do: :ets.insert(@dormancy_table, {name, step_count}),
        else: maybe_seed_dormancy(name, step_count)
    end)

    :ok
  end

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

  defp rand_between(a, b) when a >= b, do: a
  defp rand_between(a, b), do: :rand.uniform(b - a + 1) + a - 1

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
    Concept.list_all() |> Enum.each(fn name -> maybe_seed_dormancy(name, step) end)
  end

  defp maybe_seed_dormancy(name, step) do
    case :ets.lookup(@dormancy_table, name) do
      [] -> :ets.insert(@dormancy_table, {name, step})
      _ -> :ok
    end
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  defp ensure_name_available(name) do
    if name in Concept.list_all(), do: {:error, :already_exists}, else: :ok
  end

  defp register_missing_concepts(concepts) do
    existing = MapSet.new(Concept.list_all())
    missing = Enum.reject(concepts, fn c -> MapSet.member?(existing, c.name) end)
    if missing == [], do: :ok, else: Concept.register_all(missing)
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
          "tags" => concept.tags,
          "parent" => concept.parent
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
