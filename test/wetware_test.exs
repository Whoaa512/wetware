defmodule WetwareTest do
  use ExUnit.Case, async: false

  alias Wetware.{Cell, Gel, Concept, Resonance, Persistence, Params, Associations}

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

  describe "Cell" do
    test "starts with zero charge" do
      Cell.restore({0, 0}, 0.0, %{})
      state = Cell.get_state({0, 0})
      assert state.charge == 0.0
    end

    test "stimulation increases charge" do
      Cell.restore({10, 10}, 0.0, %{})
      before = Cell.get_state({10, 10}).charge

      Cell.stimulate({10, 10}, 0.5)
      after_charge = Cell.get_state({10, 10}).charge

      assert after_charge > before
      assert after_charge <= 0.5
    end

    test "charge is clamped to [0, 1]" do
      Cell.restore({11, 11}, 0.0, %{})
      Cell.stimulate({11, 11}, 0.8)
      Cell.stimulate({11, 11}, 0.8)

      state = Cell.get_state({11, 11})
      assert state.charge == 1.0
    end

    test "has exact 8-connected neighbor offsets for interior cells" do
      state = Cell.get_state({40, 40})
      actual = state.neighbors |> Map.keys() |> MapSet.new()

      expected =
        Params.neighbor_offsets()
        |> Enum.map(fn {dy, dx} -> {dx, dy} end)
        |> MapSet.new()

      assert map_size(state.neighbors) == 8
      assert actual == expected
    end

    test "corner cells have exact neighbor offsets" do
      state = Cell.get_state({0, 0})

      assert map_size(state.neighbors) == 3
      assert MapSet.new(Map.keys(state.neighbors)) == MapSet.new([{1, 0}, {0, 1}, {1, 1}])
    end

    test "edge cells have exact neighbor offsets" do
      state = Cell.get_state({0, 40})

      assert map_size(state.neighbors) == 5

      assert MapSet.new(Map.keys(state.neighbors)) ==
               MapSet.new([{0, -1}, {1, -1}, {1, 0}, {0, 1}, {1, 1}])
    end
  end

  describe "Gel" do
    test "boot is idempotent" do
      before = Registry.count(Wetware.CellRegistry)
      assert {:ok, :already_booted} = Gel.boot()
      after_count = Registry.count(Wetware.CellRegistry)

      assert before == after_count
    end
  end

  describe "charge propagation" do
    test "charge propagates to neighbors after step" do
      Cell.restore({40, 40}, 1.0, %{})
      Cell.restore({41, 40}, 0.0, %{})

      neighbor_before = Cell.get_state({41, 40}).charge
      center_before = Cell.get_state({40, 40}).charge

      assert {:ok, _} = Gel.step()

      neighbor_after = Cell.get_state({41, 40}).charge
      center_after = Cell.get_state({40, 40}).charge

      assert neighbor_after > neighbor_before
      assert center_after < center_before
    end
  end

  describe "Hebbian learning" do
    test "co-active cells strengthen direct connection" do
      Cell.restore({50, 50}, 0.8, %{})
      Cell.restore({51, 50}, 0.8, %{})

      w_before = weight_at({50, 50}, {1, 0})

      assert {:ok, _} = Gel.step()

      w_after = weight_at({50, 50}, {1, 0})

      assert w_after > w_before
      assert w_after - w_before > 0.001
    end
  end

  describe "crystallization" do
    test "connections crystallize above threshold" do
      p = Params.default()
      weights_map = uniform_weights_map({60, 60}, p.crystal_threshold + 0.02, false)

      Cell.restore({60, 60}, 0.5, weights_map)
      assert {:ok, _} = Gel.step()

      state = Cell.get_state({60, 60})

      assert Enum.all?(state.neighbors, fn {_offset, %{crystallized: c}} -> c end)
    end
  end

  describe "Concept" do
    test "loads concepts from example/concepts.json" do
      concepts = Concept.load_from_json(@example_concepts_path)
      assert is_list(concepts)
      assert length(concepts) > 0

      first = hd(concepts)
      assert %Concept{} = first
      assert is_binary(first.name)
      assert is_integer(first.cx)
      assert is_integer(first.cy)
      assert is_integer(first.r)
    end

    test "registers and lists concepts" do
      name = unique_name("test-concept")
      register_temp_concept(name, 5, 5, 2)

      all = Concept.list_all()
      assert name in all
    end

    test "stimulate and measure charge without sleep" do
      name = unique_name("test-charge")
      register_temp_concept(name, 70, 70, 2)

      charge_before = Concept.charge(name)
      Concept.stimulate(name, 0.8)
      assert {:ok, _} = Gel.step()
      charge_after = Concept.charge(name)

      assert charge_after > charge_before
    end
  end

  describe "Associations" do
    test "co_activate is symmetric and decay reduces strength" do
      assert :ok = Associations.import(%{})

      Associations.co_activate(["alpha", "beta", "beta"])
      alpha_assocs = Associations.get("alpha")
      beta_assocs = Associations.get("beta")

      assert [{"beta", alpha_weight}] = alpha_assocs
      assert [{"alpha", beta_weight}] = beta_assocs
      assert alpha_weight > 0.0
      assert beta_weight == alpha_weight

      Associations.decay(5)
      [{"beta", decayed_weight}] = Associations.get("alpha")
      assert decayed_weight < alpha_weight
    end
  end

  describe "Persistence" do
    test "save and load round-trips basic structure" do
      tmp_file = tmp_path("save_load")

      Cell.restore({30, 30}, 0.7, %{})
      assert {:ok, _} = Gel.step()

      assert :ok = Persistence.save(tmp_file)
      assert File.exists?(tmp_file)

      {:ok, data} = File.read(tmp_file)
      state = Jason.decode!(data)

      assert state["version"] == "elixir-v2"
      assert is_integer(state["step_count"])
      assert is_list(state["charges"])
      assert length(state["charges"]) == 80
      assert length(hd(state["charges"])) == 80

      assert :ok = Persistence.load(tmp_file)
      File.rm(tmp_file)
    end

    test "full save/load restores exact known state" do
      tmp_file = tmp_path("exact_roundtrip")

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
  end

  describe "Resonance API" do
    test "briefing returns expected structure" do
      b = Resonance.briefing()

      assert is_integer(b.step_count)
      assert is_integer(b.total_concepts)
      assert is_list(b.active)
      assert is_list(b.warm)
      assert is_list(b.dormant)
    end

    test "dream mode advances steps and returns echoes" do
      before = Gel.step_count()

      result = Resonance.dream(steps: 3, intensity: 0.4)

      assert %{steps: 3, echoes: echoes} = result
      assert is_list(echoes)
      assert Gel.step_count() == before + 3
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
  end

  defp weight_at({x, y}, offset) do
    Cell.get_state({x, y}).neighbors[offset].weight
  end

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

  defp register_temp_concept(name, cx, cy, r) do
    concept = %Concept{name: name, cx: cx, cy: cy, r: r, tags: ["test"]}
    assert :ok = Concept.register_all([concept])

    on_exit(fn ->
      case Registry.lookup(Wetware.ConceptRegistry, name) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Wetware.ConceptSupervisor, pid)
        [] -> :ok
      end
    end)

    concept
  end

  defp unique_name(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end
end
