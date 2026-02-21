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

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_introspect_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end
end
