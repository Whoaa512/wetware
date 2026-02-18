defmodule Wetware.VizTest do
  use ExUnit.Case, async: false

  alias Wetware.{Cell, Gel, Persistence, Resonance, Viz}

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  setup do
    baseline_path = tmp_path("viz_baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm(baseline_path)
    end)

    :ok
  end

  test "state_snapshot returns expected shape" do
    assert {:ok, _} = Gel.ensure_cell({900, 900}, :test, kind: :interstitial)
    Cell.restore({900, 900}, 0.42, %{}, kind: :interstitial)

    snapshot = Viz.state_snapshot()

    assert is_integer(snapshot.step_count)
    assert is_map(snapshot.bounds)
    assert is_list(snapshot.cells)
    assert is_list(snapshot.concepts)
    assert is_integer(snapshot.cell_count)
    assert is_integer(snapshot.max_cells)
    assert is_integer(snapshot.timestamp_ms)

    assert Enum.any?(snapshot.cells, fn cell ->
             cell.x == 900 and cell.y == 900 and is_float(cell.charge)
           end)
  end

  test "state_json is valid JSON for snapshot data" do
    json = Viz.state_json()
    decoded = Jason.decode!(json)

    assert is_map(decoded)
    assert is_list(decoded["cells"])
    assert is_list(decoded["concepts"])
    assert is_integer(decoded["step_count"])
    assert is_integer(decoded["cell_count"])
  end

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_viz_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end
end
