defmodule Wetware.IntrospectTest do
  use ExUnit.Case, async: false

  alias Wetware.{Introspect, Persistence, Resonance}

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  setup do
    baseline_path = tmp_path("introspect_baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm(baseline_path)
    end)

    :ok
  end

  test "report/0 returns full introspection payload" do
    report = Introspect.report()

    assert is_map(report)
    assert is_list(report.associations)
    assert is_list(report.crystals)
    assert is_list(report.concept_crystallization)
    assert is_list(report.neighbors)
    assert is_list(report.dormancy)
    assert is_map(report.topology)
    assert is_integer(report.topology.step_count)
    assert is_integer(report.topology.total_cells)
  end

  describe "inspect_concept/1" do
    test "returns :not_found for unknown concept" do
      assert {:error, :not_found} = Introspect.inspect_concept("nonexistent-concept-xyz")
    end

    test "returns full data for a known concept" do
      # Use a concept that definitely exists in the test gel
      concepts = Wetware.Concept.list_all()
      assert concepts != [], "need at least one concept for inspect test"

      name = hd(concepts)
      assert {:ok, data} = Introspect.inspect_concept(name)

      # Identity
      assert data.name == name
      assert is_integer(data.cx)
      assert is_integer(data.cy)
      assert is_integer(data.r)
      assert is_list(data.tags)

      # State
      assert is_float(data.charge)
      assert is_float(data.valence)

      # Dormancy
      assert is_integer(data.dormancy.dormant_steps)
      assert is_integer(data.dormancy.last_active_step)
      assert is_integer(data.dormancy.current_step)

      # Cells
      assert is_integer(data.cells.total)
      assert data.cells.total > 0
      assert is_integer(data.cells.live)
      assert is_integer(data.cells.snapshot)
      assert is_integer(data.cells.dead)
      assert data.cells.live + data.cells.snapshot + data.cells.dead == data.cells.total
      assert is_list(data.cells.charge_distribution)

      if data.cells.charge_distribution != [] do
        sample = hd(data.cells.charge_distribution)
        assert is_integer(sample.x)
        assert is_integer(sample.y)
        assert is_float(sample.charge) or is_integer(sample.charge)
      end

      # Associations
      assert is_list(data.associations)

      # Crystal bonds
      assert is_list(data.crystal_bonds)

      # Internal crystallization
      assert is_map(data.internal_crystallization)
      assert is_integer(data.internal_crystallization.total_bonds)
      assert is_integer(data.internal_crystallization.crystal_bonds)

      # Spatial neighbors
      assert is_list(data.spatial_neighbors)
    end

    test "inspect returns children list" do
      concepts = Wetware.Concept.list_all()
      name = hd(concepts)
      {:ok, data} = Introspect.inspect_concept(name)
      assert is_list(data.children)
    end

    test "print_inspect handles unknown concepts" do
      # Should print error without crashing
      assert :ok == Introspect.print_inspect("nonexistent-xyz-123")
    end

    test "print_inspect works for known concepts" do
      concepts = Wetware.Concept.list_all()
      name = hd(concepts)
      # Should print without crashing
      assert :ok == Introspect.print_inspect(name)
    end
  end

  describe "drift_check" do
    test "drift_check returns list" do
      result = Introspect.drift_check()
      assert is_list(result)
    end

    test "print_drift_check runs without error" do
      assert :ok == Introspect.print_drift_check()
    end
  end

  describe "raw_position" do
    test "Concept.raw_position returns GenServer's own position" do
      name = hd(Wetware.Concept.list_all())
      pos = Wetware.Concept.raw_position(name)
      assert is_map(pos)
      assert Map.has_key?(pos, :cx)
      assert Map.has_key?(pos, :cy)
      assert Map.has_key?(pos, :r)
    end
  end

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_introspect_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end
end
