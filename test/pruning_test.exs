defmodule Wetware.PruningTest do
  use ExUnit.Case, async: false

  alias Wetware.{Cell, Concept, DataPaths, Pruning, Resonance}

  setup_all do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "wetware_pruning_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)

    prev = System.get_env("WETWARE_DATA_DIR")
    System.put_env("WETWARE_DATA_DIR", tmp_dir)

    seed_concepts(tmp_dir)
    Resonance.boot(concepts_path: DataPaths.concepts_path())

    on_exit(fn ->
      if prev,
        do: System.put_env("WETWARE_DATA_DIR", prev),
        else: System.delete_env("WETWARE_DATA_DIR")

      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  setup do
    File.rm(DataPaths.pruned_history_path())
    :ok
  end

  test "dormant concept becomes prune candidate and can be pruned" do
    name = unique("dormant")

    {:ok, _} =
      Resonance.add_concept(%Concept{name: name, cx: 55, cy: 55, r: 3, tags: ["test"]},
        concepts_path: DataPaths.concepts_path()
      )

    :ok = Wetware.Gel.set_step_count(1200)
    :ets.insert(:wetware_dormancy, {name, 0})

    candidates = Pruning.candidates(dormancy_steps: 500)
    assert Enum.any?(candidates, &(&1.name == name))

    assert :ok = Pruning.prune(name)
    refute name in Concept.list_all()

    history = Jason.decode!(File.read!(DataPaths.pruned_history_path()))
    assert Enum.any?(history["entries"], &(&1["concept"] == name))
  end

  test "crystallized concepts are never pruned" do
    name = unique("crystal")

    {:ok, _} =
      Resonance.add_concept(%Concept{name: name, cx: 65, cy: 20, r: 3, tags: ["test"]},
        concepts_path: DataPaths.concepts_path()
      )

    crystallize_cell({65, 20})

    :ok = Wetware.Gel.set_step_count(1200)
    :ets.insert(:wetware_dormancy, {name, 0})

    candidates = Pruning.candidates(dormancy_steps: 10)
    refute Enum.any?(candidates, &(&1.name == name))

    assert {:error, :crystallized} = Pruning.prune(name)
    assert :ok = Resonance.remove_concept(name)
  end

  defp crystallize_cell({x, y}) do
    weights =
      Cell.get_state({x, y}).neighbors
      |> Enum.map(fn {offset, %{weight: w}} -> {offset, %{weight: w, crystallized: true}} end)
      |> Map.new()

    Cell.restore({x, y}, 0.0, weights)
  end

  defp seed_concepts(tmp_dir) do
    concepts = %{
      "concepts" => %{
        "seed" => %{"tags" => ["seed"]}
      }
    }

    File.write!(Path.join(tmp_dir, "concepts.json"), Jason.encode!(concepts, pretty: true))
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
