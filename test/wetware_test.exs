defmodule WetwareTest do
  use ExUnit.Case, async: false

  alias Wetware.{
    Associations,
    Cell,
    Concept,
    Gel,
    Params,
    Persistence,
    PrimingOverrides,
    Resonance
  }

  @example_concepts_path Path.expand("example/concepts.json", File.cwd!())

  setup_all do
    case Gel.boot() do
      :ok -> :ok
      {:ok, :already_booted} -> :ok
    end

    ensure_example_concepts_loaded!()
    :ok
  end

  setup do
    baseline_path = tmp_path("baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm(baseline_path)
    end)

    :ok
  end

  describe "Sparse Cell" do
    test "starts with zero charge" do
      {:ok, _} = Gel.ensure_cell({0, 0}, :test)
      Cell.restore({0, 0}, 0.0, %{})
      assert Cell.get_state({0, 0}).charge == 0.0
    end

    test "stimulation increases charge" do
      {:ok, _} = Gel.ensure_cell({10, 10}, :test)
      Cell.restore({10, 10}, 0.0, %{})
      before = Cell.get_state({10, 10}).charge

      Cell.stimulate({10, 10}, 0.5)
      after_charge = Cell.get_state({10, 10}).charge

      assert after_charge > before
      assert after_charge <= 0.5
    end

    test "on-demand neighbors wire between existing cells" do
      {:ok, _} = Gel.ensure_cell({40, 40}, :test)
      {:ok, _} = Gel.ensure_cell({41, 40}, :test)

      s1 = Cell.get_state({40, 40})
      s2 = Cell.get_state({41, 40})

      assert Map.has_key?(s1.neighbors, {1, 0})
      assert Map.has_key?(s2.neighbors, {-1, 0})
    end
  end

  describe "Sparse Gel" do
    test "boot is idempotent" do
      before = Registry.count(Wetware.CellRegistry)
      assert {:ok, :already_booted} = Gel.boot()
      after_count = Registry.count(Wetware.CellRegistry)
      assert before == after_count
    end

    test "starts with sparse non-zero count after concept seed" do
      assert Registry.count(Wetware.CellRegistry) > 0
      assert Registry.count(Wetware.CellRegistry) < 6_400
    end

    test "spawn threshold gates propagation into empty space" do
      source = {500, 500}
      target = {501, 500}

      {:ok, _} = Gel.ensure_cell(source, :test, kind: :concept)
      Cell.restore(source, 1.0, %{}, kind: :concept)

      assert :error = Wetware.Gel.Index.cell_pid(target)

      assert {:ok, _} = Gel.step()
      assert :error = Wetware.Gel.Index.cell_pid(target)

      Enum.each(1..8, fn _ ->
        Cell.stimulate(source, 1.0)
        assert {:ok, _} = Gel.step()
      end)

      assert {:ok, _pid} = Wetware.Gel.Index.cell_pid(target)
    end

    test "self-reshaping topology creates non-grid links for co-active cells" do
      a = {600, 600}
      b = {603, 600}

      {:ok, _} = Gel.ensure_cell(a, :test, kind: :concept)
      {:ok, _} = Gel.ensure_cell(b, :test, kind: :concept)

      Cell.restore(a, 0.9, %{}, kind: :concept)
      Cell.restore(b, 0.9, %{}, kind: :concept)

      refute Map.has_key?(Cell.get_state(a).neighbors, {3, 0})
      refute Map.has_key?(Cell.get_state(b).neighbors, {-3, 0})

      Enum.each(1..8, fn _ ->
        Cell.stimulate(a, 1.0)
        Cell.stimulate(b, 1.0)
        assert {:ok, _} = Gel.step()
      end)

      assert Map.has_key?(Cell.get_state(a).neighbors, {3, 0})
      assert Map.has_key?(Cell.get_state(b).neighbors, {-3, 0})
    end
  end

  describe "Application wiring" do
    test "partition supervisor and sparse index/lifecycle are running" do
      assert is_pid(Process.whereis(Wetware.CellSupervisors))
      assert is_pid(Process.whereis(Wetware.Gel.Index))
      assert is_pid(Process.whereis(Wetware.Gel.Lifecycle))
      assert is_pid(Process.whereis(Wetware.Layout.Engine))
    end
  end

  describe "Cell kinds" do
    test "kind-specific physics produce distinct decay profiles" do
      concept_coord = {520, 520}
      axon_coord = {540, 540}
      interstitial_coord = {560, 560}

      {:ok, _} = Gel.ensure_cell(concept_coord, :test, kind: :concept)
      {:ok, _} = Gel.ensure_cell(axon_coord, :test, kind: :axon)
      {:ok, _} = Gel.ensure_cell(interstitial_coord, :test, kind: :interstitial)

      Cell.restore(concept_coord, 1.0, %{}, kind: :concept)
      Cell.restore(axon_coord, 1.0, %{}, kind: :axon)
      Cell.restore(interstitial_coord, 1.0, %{}, kind: :interstitial)

      assert {:ok, _} = Gel.step()

      concept = Cell.get_state(concept_coord).charge
      axon = Cell.get_state(axon_coord).charge
      interstitial = Cell.get_state(interstitial_coord).charge

      assert axon > concept
      assert concept > interstitial
    end
  end

  describe "charge propagation" do
    test "charge propagates to neighbors after step" do
      {:ok, _} = Gel.ensure_cell({50, 50}, :test)
      {:ok, _} = Gel.ensure_cell({51, 50}, :test)

      Cell.restore({50, 50}, 1.0, %{})
      Cell.restore({51, 50}, 0.0, %{})

      neighbor_before = Cell.get_state({51, 50}).charge
      center_before = Cell.get_state({50, 50}).charge

      assert {:ok, _} = Gel.step()

      neighbor_after = Cell.get_state({51, 50}).charge
      center_after = Cell.get_state({50, 50}).charge

      assert neighbor_after > neighbor_before
      assert center_after < center_before
    end
  end

  describe "Hebbian learning" do
    test "co-active cells strengthen direct connection" do
      {:ok, _} = Gel.ensure_cell({60, 60}, :test, kind: :concept)
      {:ok, _} = Gel.ensure_cell({61, 60}, :test, kind: :concept)

      Cell.restore({60, 60}, 0.8, %{}, kind: :concept)
      Cell.restore({61, 60}, 0.8, %{}, kind: :concept)

      w_before = weight_at({60, 60}, {1, 0})

      assert {:ok, _} = Gel.step()

      w_after = weight_at({60, 60}, {1, 0})
      assert w_after > w_before
    end
  end

  describe "crystallization" do
    test "connections crystallize above threshold" do
      {:ok, _} = Gel.ensure_cell({70, 70}, :test)
      {:ok, _} = Gel.ensure_cell({71, 70}, :test)

      p = Params.default()
      weights_map = uniform_weights_map({70, 70}, p.crystal_threshold + 0.02, false)

      Cell.restore({70, 70}, 0.5, weights_map)
      assert {:ok, _} = Gel.step()

      state = Cell.get_state({70, 70})
      assert Enum.all?(state.neighbors, fn {_offset, %{crystallized: c}} -> c end)
    end
  end

  describe "Concept" do
    test "loads concepts from example/concepts.json" do
      concepts = Concept.load_from_json(@example_concepts_path)
      assert is_list(concepts)
      assert length(concepts) > 0
      assert %Concept{} = hd(concepts)
    end

    test "registers and lists concepts" do
      name = unique_name("test-concept")
      register_temp_concept(name, 5, 5, 2)
      assert name in Concept.list_all()
    end

    test "stimulate and measure charge" do
      name = unique_name("test-charge")
      register_temp_concept(name, 80, 80, 2)

      charge_before = Concept.charge(name)
      Concept.stimulate(name, 0.8)
      assert {:ok, _} = Gel.step()
      charge_after = Concept.charge(name)

      assert charge_after > charge_before
    end

    test "registering a concept seeds concept-kind cells in its region" do
      name = unique_name("seed-kind")
      concept = register_temp_concept(name, 90, 90, 2)

      seeded_cells = Gel.concept_cells(name)
      assert seeded_cells != []

      assert Enum.all?(seeded_cells, fn {x, y} ->
               Cell.get_state({x, y}).kind == :concept and
                 name in Cell.get_state({x, y}).owners
             end)

      assert concept.name == name
    end
  end

  describe "Associations" do
    test "co_activate is symmetric and decay reduces strength" do
      assert :ok = Associations.import(%{})

      Associations.co_activate(["alpha", "beta", "beta"])
      assert [{"beta", alpha_weight}] = Associations.get("alpha")
      assert [{"alpha", beta_weight}] = Associations.get("beta")
      assert beta_weight == alpha_weight

      Associations.decay(5)
      [{"beta", decayed_weight}] = Associations.get("alpha")
      assert decayed_weight < alpha_weight
    end
  end

  describe "Persistence" do
    test "save and load round-trips sparse structure" do
      tmp_file = tmp_path("save_load")

      {:ok, _} = Gel.ensure_cell({30, 30}, :test)
      Cell.restore({30, 30}, 0.7, %{})
      assert {:ok, _} = Gel.step()

      assert :ok = Persistence.save(tmp_file)
      assert File.exists?(tmp_file)

      state = Jason.decode!(File.read!(tmp_file))

      assert state["version"] == "elixir-v3-sparse"
      assert is_integer(state["step_count"])
      assert is_map(state["cells"])
      assert map_size(state["cells"]) > 0

      assert :ok = Persistence.load(tmp_file)
      File.rm(tmp_file)
    end

    test "full save/load restores exact known state" do
      tmp_file = tmp_path("exact_roundtrip")

      {:ok, _} = Gel.ensure_cell({20, 20}, :test)
      {:ok, _} = Gel.ensure_cell({21, 20}, :test)

      weights_a = custom_weight_map({20, 20}, 0.2, 0.01)
      weights_b = custom_weight_map({21, 20}, 0.5, 0.02)

      Cell.restore({20, 20}, 0.333333, weights_a)
      Cell.restore({21, 20}, 0.777777, weights_b)
      assert :ok = Gel.set_step_count(123)
      assert :ok = Associations.import(%{"alpha|beta" => 0.42})

      expected_a = Cell.get_state({20, 20})
      expected_b = Cell.get_state({21, 20})

      assert :ok = Persistence.save(tmp_file)

      Cell.restore({20, 20}, 0.0, %{})
      Cell.restore({21, 20}, 0.0, %{})
      assert :ok = Gel.set_step_count(0)
      assert :ok = Associations.import(%{})

      assert :ok = Persistence.load(tmp_file)

      actual_a = Cell.get_state({20, 20})
      actual_b = Cell.get_state({21, 20})

      assert actual_a.charge == expected_a.charge
      assert actual_b.charge == expected_b.charge
      assert actual_a.neighbors == expected_a.neighbors
      assert actual_b.neighbors == expected_b.neighbors
      assert Gel.step_count() == 123
      assert [{"beta", 0.42}] == Associations.get("alpha")

      File.rm(tmp_file)
    end

    test "load returns file_read error for missing file" do
      missing = tmp_path("missing")
      File.rm(missing)
      assert {:error, {:file_read, :enoent}} = Persistence.load(missing)
    end

    test "load returns json_parse error for invalid json" do
      bad = tmp_path("bad_json")
      File.write!(bad, "not json")

      assert {:error, {:json_parse, _reason}} = Persistence.load(bad)
      File.rm(bad)
    end

    test "load migrates legacy elixir-v2 dense state" do
      legacy = tmp_path("legacy_v2")

      payload = %{
        "version" => "elixir-v2",
        "step_count" => 9,
        "charges" => [
          [0.0, 0.2],
          [0.0, 0.0]
        ],
        "weights" => [
          [
            List.duplicate(0.1, 8),
            List.duplicate(0.2, 8)
          ],
          [
            List.duplicate(0.1, 8),
            List.duplicate(0.1, 8)
          ]
        ],
        "crystallized" => [
          [
            List.duplicate(false, 8),
            List.duplicate(false, 8)
          ],
          [
            List.duplicate(false, 8),
            List.duplicate(false, 8)
          ]
        ],
        "concepts" => %{
          "legacy" => %{"cx" => 1, "cy" => 0, "r" => 2, "tags" => ["old"]}
        }
      }

      File.write!(legacy, Jason.encode!(payload, pretty: true))
      assert :ok = Persistence.load(legacy)
      assert Gel.step_count() == 9
      assert {:ok, _pid} = Wetware.Gel.Index.cell_pid({1, 0})
      assert %{charge: charge} = Cell.get_state({1, 0})
      assert charge > 0.0
      File.rm(legacy)
    end
  end

  describe "Lifecycle" do
    test "dormancy sweep despawns dormant non-crystallized cells" do
      coord = {580, 580}
      {:ok, _} = Gel.ensure_cell(coord, :test, kind: :interstitial)

      Cell.restore(coord, 0.0, %{},
        kind: :interstitial,
        last_step: 0,
        last_active_step: 0
      )

      Wetware.Gel.Lifecycle.tick(10_000)
      send(Wetware.Gel.Lifecycle, :sweep)

      wait_until(fn -> match?(:error, Wetware.Gel.Index.cell_pid(coord)) end)
      assert :error = Wetware.Gel.Index.cell_pid(coord)
    end
  end

  describe "Resonance API" do
    test "briefing returns expected structure" do
      b = Resonance.briefing()
      assert is_integer(b.step_count)
      assert is_integer(b.total_concepts)
      assert is_list(b.active)
      assert is_list(b.warm)
      assert is_list(b.dormant)
      assert is_list(b.disposition_hints)
    end

    test "priming payload provides transparent tokens and prompt block" do
      payload = Resonance.priming_payload()

      assert is_list(payload.tokens)
      assert is_list(payload.disposition_hints)
      assert is_binary(payload.prompt_block)
      assert payload.transparent == true
      assert is_list(payload.override_keys)
      assert String.contains?(payload.prompt_block, "[WETWARE_PRIMING_BEGIN]")
    end

    test "gentleness priming appears when care and conflict are warm" do
      conflict = unique_name("conflict")
      care = unique_name("care")

      _ = register_temp_concept(conflict, 310, 310, 2, ["emotion:conflict"])
      _ = register_temp_concept(care, 330, 310, 2, ["care", "gentleness"])

      assert :ok = Resonance.imprint([conflict, care], steps: 2, strength: 0.8)
      payload = Resonance.priming_payload()

      assert Enum.any?(payload.disposition_hints, fn hint ->
               (hint[:id] || hint["id"]) == "lean_gentle"
             end)
    end

    test "disabled priming override removes hint from effective payload" do
      conflict = unique_name("conflict")
      care = unique_name("care")

      _ = register_temp_concept(conflict, 350, 350, 2, ["emotion:conflict"])
      _ = register_temp_concept(care, 370, 350, 2, ["care", "gentleness"])

      assert :ok = Resonance.imprint([conflict, care], steps: 2, strength: 0.8)
      :ok = PrimingOverrides.set_enabled("gentleness", false)

      on_exit(fn -> :ok = PrimingOverrides.set_enabled("gentleness", true) end)

      payload = Resonance.priming_payload()
      assert "gentleness" in payload.disabled_overrides

      refute Enum.any?(payload.disposition_hints, fn hint ->
               (hint[:override_key] || hint["override_key"]) == "gentleness"
             end)
    end

    test "dream mode advances steps and returns echoes" do
      before = Gel.step_count()
      result = Resonance.dream(steps: 3, intensity: 0.4)
      assert %{steps: 3, echoes: echoes} = result
      assert is_list(echoes)
      assert Gel.step_count() == before + 3
    end

    test "imprint supports continuous valence in [-1.0, 1.0]" do
      name = unique_name("valence")
      _ = register_temp_concept(name, 30, 30, 2)

      before = Concept.valence(name)
      assert :ok = Resonance.imprint([name], steps: 2, strength: 0.8, valence: -0.75)
      after_negative = Concept.valence(name)

      assert after_negative < before
      assert after_negative < 0.0

      assert :ok = Resonance.imprint([name], steps: 1, strength: 0.8, valence: 5.0)
      after_clamped = Concept.valence(name)
      assert after_clamped <= 1.0
      assert after_clamped >= -1.0
    end

    test "conflict context dampens assertive and amplifies care/listening" do
      conflict = unique_name("conflict")
      care = unique_name("care")
      assertive = unique_name("assertive")

      _ = register_temp_concept(conflict, 120, 120, 2, ["domain:emotional", "emotion:conflict"])
      _ = register_temp_concept(care, 140, 120, 2, ["care", "listening"])
      _ = register_temp_concept(assertive, 160, 120, 2, ["assertive"])

      assert :ok = Resonance.imprint([conflict], steps: 2, strength: 0.9)
      care_before = Concept.charge(care)
      assertive_before = Concept.charge(assertive)

      assert :ok = Resonance.imprint([care, assertive], steps: 1, strength: 0.6)
      care_delta = Concept.charge(care) - care_before
      assertive_delta = Concept.charge(assertive) - assertive_before

      assert care_delta > assertive_delta
    end

    test "imprint step briefing lifecycle" do
      concept_names = ["coding", "research"]
      before_step = Gel.step_count()

      before_charges =
        concept_names
        |> Enum.map(fn name -> {name, Concept.charge(name)} end)
        |> Map.new()

      assert :ok = Resonance.imprint(concept_names, steps: 2, strength: 0.7)
      assert {:ok, _} = Gel.step()

      briefing = Resonance.briefing()

      assert briefing.step_count == before_step + 3
      assert briefing.total_concepts >= length(concept_names)

      assert Enum.any?(concept_names, fn name ->
               Concept.charge(name) > Map.fetch!(before_charges, name)
             end)
    end

    test "phase 1 sparse flow works end-to-end" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "wetware_phase1_#{System.unique_integer([:positive, :monotonic])}"
        )

      File.mkdir_p!(tmp_dir)
      concepts_path = Path.join(tmp_dir, "concepts.json")
      state_path = Path.join(tmp_dir, "gel_state.json")
      File.write!(concepts_path, Jason.encode!(%{"concepts" => %{}}, pretty: true))

      name = unique_name("phase1")

      assert :ok = Gel.reset_cells()
      assert wait_for_registry_at_most(1)

      assert {:ok, concept} =
               Resonance.add_concept(
                 %Concept{name: name, r: 3, tags: ["phase1", "integration"]},
                 concepts_path: concepts_path
               )

      assert concept.name == name
      assert Registry.count(Wetware.CellRegistry) > 0

      charge_before = Concept.charge(name)
      assert :ok = Resonance.imprint([name], steps: 2, strength: 0.8)
      assert {:ok, _} = Gel.step()
      charge_after = Concept.charge(name)
      assert charge_after > charge_before

      briefing = Resonance.briefing()
      assert briefing.total_concepts >= 1
      assert is_list(briefing.active)
      assert is_list(briefing.warm)
      assert is_list(briefing.dormant)

      assert :ok = Resonance.save(state_path)
      assert :ok = Gel.reset_cells()
      assert wait_for_registry_at_most(1)
      assert :ok = Resonance.load(state_path)
      assert Registry.count(Wetware.CellRegistry) > 0
      assert Concept.charge(name) > 0.0

      assert :ok = Resonance.remove_concept(name, concepts_path: concepts_path)
      File.rm_rf(tmp_dir)
    end
  end

  defp weight_at({x, y}, offset), do: Cell.get_state({x, y}).neighbors[offset].weight

  defp uniform_weights_map({x, y}, weight, crystallized) do
    Cell.get_state({x, y}).neighbors
    |> Map.keys()
    |> Enum.map(fn offset -> {offset, %{weight: weight, crystallized: crystallized}} end)
    |> Map.new()
  end

  defp custom_weight_map({x, y}, base, step) do
    Cell.get_state({x, y}).neighbors
    |> Enum.sort_by(fn {offset, _} -> offset end)
    |> Enum.with_index()
    |> Enum.map(fn {{offset, _}, i} ->
      weight = Float.round(base + step * i, 6)
      {offset, %{weight: weight, crystallized: rem(i, 2) == 0}}
    end)
    |> Map.new()
  end

  defp wait_for_registry_at_most(max, tries \\ 120)

  defp wait_for_registry_at_most(max, tries) when tries <= 0,
    do: Registry.count(Wetware.CellRegistry) <= max

  defp wait_for_registry_at_most(max, tries) do
    if Registry.count(Wetware.CellRegistry) <= max do
      true
    else
      Process.sleep(10)
      wait_for_registry_at_most(max, tries - 1)
    end
  end

  defp ensure_example_concepts_loaded! do
    loaded = Concept.load_from_json(@example_concepts_path)
    assert is_list(loaded)

    existing = MapSet.new(Concept.list_all())
    missing = Enum.reject(loaded, fn concept -> MapSet.member?(existing, concept.name) end)

    if missing != [] do
      assert :ok = Concept.register_all(missing)
    end

    :ok
  end

  defp register_temp_concept(name, cx, cy, r, tags \\ ["test"]) do
    concept = %Concept{name: name, cx: cx, cy: cy, r: r, tags: tags}
    assert :ok = Concept.register_all([concept])

    on_exit(fn ->
      case Registry.lookup(Wetware.ConceptRegistry, name) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Wetware.ConceptSupervisor, pid)
        [] -> :ok
      end
    end)

    concept
  end

  defp unique_name(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end

  defp wait_until(fun, attempts \\ 30)

  defp wait_until(fun, attempts) when attempts <= 0 do
    assert fun.()
  end

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end
end
