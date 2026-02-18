defmodule Wetware.SmokeLifecycleTest do
  use ExUnit.Case, async: false

  alias Wetware.{Concept, Gel, Persistence, Resonance}

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  setup do
    baseline_path = tmp_path("smoke_baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm(baseline_path)
    end)

    :ok
  end

  test "happy path lifecycle: add concept, imprint, briefing, dream, save/load" do
    tmp_dir = tmp_dir("smoke_happy")
    concepts_path = Path.join(tmp_dir, "concepts.json")
    state_path = Path.join(tmp_dir, "gel_state.json")
    File.write!(concepts_path, Jason.encode!(%{"concepts" => %{}}, pretty: true))

    assert :ok = Gel.reset_cells()
    assert wait_for_registry_at_most(1)

    name = unique_name("smoke")

    assert {:ok, concept} =
             Resonance.add_concept(%Concept{name: name, r: 3, tags: ["smoke"]},
               concepts_path: concepts_path
             )

    assert concept.name == name

    assert :ok = Resonance.imprint([name], steps: 2, strength: 0.8)
    briefing = Resonance.briefing()
    assert briefing.total_concepts >= 1

    assert Enum.any?(briefing.active ++ briefing.warm, fn {concept_name, _charge} ->
             concept_name == name
           end)

    assert %{steps: 2, echoes: echoes} = Resonance.dream(steps: 2, intensity: 0.35)
    assert is_list(echoes)

    assert :ok = Resonance.save(state_path)
    assert :ok = Gel.reset_cells()
    assert wait_for_registry_at_most(1)
    assert :ok = Resonance.load(state_path)
    assert Registry.count(Wetware.CellRegistry) > 0
    assert Concept.charge(name) > 0.0

    assert :ok = Resonance.remove_concept(name, concepts_path: concepts_path)
    File.rm_rf(tmp_dir)
  end

  test "edge path lifecycle handles empty concepts and missing load file" do
    tmp_dir = tmp_dir("smoke_edge")
    state_path = Path.join(tmp_dir, "empty_state.json")
    missing_path = Path.join(tmp_dir, "missing.json")

    assert :ok = Gel.reset_cells()
    assert wait_for_registry_at_most(1)

    briefing = Resonance.briefing()
    assert briefing.total_concepts >= 0
    assert is_list(briefing.active)
    assert is_list(briefing.warm)
    assert is_list(briefing.dormant)

    assert %{steps: 1, echoes: echoes} = Resonance.dream(steps: 1, intensity: 0.2)
    assert is_list(echoes)

    assert :ok = Resonance.save(state_path)
    assert :ok = Resonance.load(state_path)
    assert {:error, {:file_read, :enoent}} = Resonance.load(missing_path)

    File.rm_rf(tmp_dir)
  end

  defp unique_name(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp tmp_dir(prefix) do
    path =
      Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(path)
    path
  end

  defp tmp_path(prefix) do
    Path.join(
      System.tmp_dir!(),
      "#{prefix}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
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
end
