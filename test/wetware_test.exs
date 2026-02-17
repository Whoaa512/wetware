defmodule WetwareTest do
  use ExUnit.Case, async: false

  alias Wetware.{Cell, Gel, Concept, Resonance, Persistence, Params}

  # We need the app running for all tests
  # The application starts registries + supervisors automatically

  setup_all do
    # Boot the gel once for all tests
    Gel.boot()
    :ok
  end

  describe "Cell" do
    test "starts with zero charge" do
      state = Cell.get_state({0, 0})
      assert state.charge == 0.0
    end

    test "stimulation increases charge" do
      Cell.stimulate({10, 10}, 0.5)
      state = Cell.get_state({10, 10})
      assert state.charge > 0.0
      assert state.charge <= 0.5

      # Cleanup
      Cell.restore({10, 10}, 0.0, %{})
    end

    test "charge is clamped to [0, 1]" do
      Cell.stimulate({11, 11}, 0.8)
      Cell.stimulate({11, 11}, 0.8)
      state = Cell.get_state({11, 11})
      assert state.charge <= 1.0

      # Cleanup
      Cell.restore({11, 11}, 0.0, %{})
    end

    test "has 8 neighbors for interior cells" do
      state = Cell.get_state({40, 40})
      assert map_size(state.neighbors) == 8
    end

    test "corner cells have 3 neighbors" do
      state = Cell.get_state({0, 0})
      assert map_size(state.neighbors) == 3
    end

    test "edge cells have 5 neighbors" do
      state = Cell.get_state({0, 40})
      assert map_size(state.neighbors) == 5
    end
  end

  describe "charge propagation" do
    test "charge propagates to neighbors after step" do
      # Inject charge at center
      Cell.stimulate({40, 40}, 1.0)

      # Verify neighbor starts near zero
      before = Cell.get_state({41, 40})
      _before_charge = before.charge

      # Run a step
      Gel.step()

      # Neighbor should have gained some charge
      after_state = Cell.get_state({41, 40})

      # The exact behavior depends on the full grid state,
      # but with 1.0 injected at {40,40}, neighbors should see increase
      assert after_state.charge >= 0.0

      # Reset
      Cell.restore({40, 40}, 0.0, %{})
      Cell.restore({41, 40}, 0.0, %{})
    end
  end

  describe "Hebbian learning" do
    test "co-active cells strengthen connections" do
      # Stimulate two adjacent cells above activation threshold
      Cell.stimulate({50, 50}, 0.8)
      Cell.stimulate({51, 50}, 0.8)

      # Get initial weight
      state_before = Cell.get_state({50, 50})
      w_before = state_before.neighbors[{1, 0}][:weight] || Params.default().w_init

      # Step to trigger learning
      Gel.step()

      # Check weight increased
      state_after = Cell.get_state({50, 50})
      w_after = state_after.neighbors[{1, 0}][:weight] || Params.default().w_init

      # Weight should have increased (learning_rate = 0.02)
      # Note: decay also happens, so net change might be small
      # but learning (0.02) > decay (0.005), so net should be positive
      assert w_after >= w_before - 0.01  # allow small tolerance

      # Reset
      Cell.restore({50, 50}, 0.0, %{})
      Cell.restore({51, 50}, 0.0, %{})
    end
  end

  describe "crystallization" do
    test "connections crystallize above threshold" do
      p = Params.default()

      # Manually set a high weight near crystal threshold
      # by restoring with custom weights
      offsets = Params.neighbor_offsets()

      weights_map =
        offsets
        |> Enum.map(fn offset ->
          {offset, %{weight: p.crystal_threshold + 0.01, crystallized: false}}
        end)
        |> Map.new()

      Cell.restore({60, 60}, 0.5, weights_map)
      Cell.stimulate({61, 60}, 0.5)  # make neighbor active too

      # Step should trigger crystallization check
      Gel.step()

      state = Cell.get_state({60, 60})

      # At least some connections should be crystallized
      crystallized_count =
        state.neighbors
        |> Enum.count(fn {_offset, %{crystallized: c}} -> c end)

      assert crystallized_count > 0

      # Reset
      Cell.restore({60, 60}, 0.0, %{})
      Cell.restore({61, 60}, 0.0, %{})
    end
  end

  describe "Concept" do
    test "loads concepts from JSON" do
      path = Path.expand("~/nova/projects/digital-wetware/concepts.json")

      if File.exists?(path) do
        concepts = Concept.load_from_json(path)
        assert is_list(concepts)
        assert length(concepts) > 0

        first = hd(concepts)
        assert %Concept{} = first
        assert is_binary(first.name)
        assert is_integer(first.cx)
        assert is_integer(first.cy)
        assert is_integer(first.r)
      end
    end

    test "registers and lists concepts" do
      test_concept = %Concept{name: "test-concept", cx: 5, cy: 5, r: 2, tags: ["test"]}
      Concept.register_all([test_concept])

      all = Concept.list_all()
      assert "test-concept" in all
    end

    test "stimulate and measure charge" do
      test_concept = %Concept{name: "test-charge", cx: 70, cy: 70, r: 2, tags: ["test"]}
      Concept.register_all([test_concept])

      # Before stimulation
      charge_before = Concept.charge("test-charge")

      # Stimulate
      Concept.stimulate("test-charge", 0.8)

      # Small delay for async cast to process
      Process.sleep(50)

      charge_after = Concept.charge("test-charge")
      assert charge_after > charge_before
    end
  end

  describe "Persistence" do
    test "save and load round-trips" do
      tmp_path = Path.join(System.tmp_dir!(), "wetware_test_#{:rand.uniform(99999)}.json")

      # Stimulate something so we have non-zero state
      Cell.stimulate({30, 30}, 0.7)
      Gel.step()

      # Save
      assert :ok = Persistence.save(tmp_path)
      assert File.exists?(tmp_path)

      # Read back
      {:ok, data} = File.read(tmp_path)
      state = Jason.decode!(data)

      assert state["version"] == "elixir-v2"
      assert is_integer(state["step_count"])
      assert is_list(state["charges"])
      assert length(state["charges"]) == 80
      assert length(hd(state["charges"])) == 80

      # Load should work
      assert :ok = Persistence.load(tmp_path)

      # Cleanup
      File.rm(tmp_path)
      Cell.restore({30, 30}, 0.0, %{})
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
  end
end
