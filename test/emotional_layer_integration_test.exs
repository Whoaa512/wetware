defmodule Wetware.EmotionalLayerIntegrationTest do
  use ExUnit.Case, async: false

  alias Wetware.{Concept, Gel, Persistence, Resonance}

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  setup do
    baseline_path = tmp_path("emotional_baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm(baseline_path)
    end)

    :ok
  end

  test "valence imprint persists through save/load lifecycle" do
    tmp_dir = tmp_dir("emotional_persist")
    concepts_path = Path.join(tmp_dir, "concepts.json")
    state_path = Path.join(tmp_dir, "gel_state.json")
    File.write!(concepts_path, Jason.encode!(%{"concepts" => %{}}, pretty: true))

    name = unique_name("emotion_persist")

    assert {:ok, _concept} =
             Resonance.add_concept(%Concept{name: name, r: 3, tags: ["domain:emotional"]},
               concepts_path: concepts_path
             )

    assert :ok = Resonance.imprint([name], steps: 2, strength: 0.8, valence: -0.7)
    valence_before = Concept.valence(name)
    assert valence_before < 0.0

    assert :ok = Resonance.save(state_path)
    assert :ok = Gel.reset_cells()
    assert :ok = Resonance.load(state_path)
    valence_after = Concept.valence(name)

    assert valence_after < 0.0
    assert abs(valence_after - valence_before) < 0.3

    assert :ok = Resonance.remove_concept(name, concepts_path: concepts_path)
    File.rm_rf(tmp_dir)
  end

  test "conflict warmth amplifies care/listening over assertive response" do
    conflict = unique_name("conflict")
    care = unique_name("care")
    assertive = unique_name("assertive")

    _ = register_temp_concept(conflict, 210, 210, 2, ["domain:emotional", "emotion:conflict"])
    _ = register_temp_concept(care, 230, 210, 2, ["care", "listening"])
    _ = register_temp_concept(assertive, 250, 210, 2, ["assertive"])

    assert :ok = Resonance.imprint([conflict], steps: 2, strength: 0.9)
    care_before = Concept.charge(care)
    assertive_before = Concept.charge(assertive)

    assert :ok = Resonance.imprint([care, assertive], steps: 1, strength: 0.6)
    care_delta = Concept.charge(care) - care_before
    assertive_delta = Concept.charge(assertive) - assertive_before

    assert care_delta > assertive_delta
  end

  defp register_temp_concept(name, cx, cy, r, tags) do
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

  defp tmp_dir(prefix) do
    path =
      Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(path)
    path
  end

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_emotional_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end
end
