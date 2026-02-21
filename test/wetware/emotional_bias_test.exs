defmodule Wetware.EmotionalBiasTest do
  use ExUnit.Case, async: false

  alias Wetware.{Concept, EmotionalBias, Persistence, Resonance}

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  setup do
    baseline_path = tmp_path("emotional_bias_baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm(baseline_path)
    end)

    :ok
  end

  test "strength_multiplier/1 dampens assertive and boosts care under conflict" do
    conflict = unique_name("conflict")
    care = unique_name("care")
    assertive = unique_name("assertive")

    _ = register_temp_concept(conflict, 410, 410, 2, ["emotion:conflict"])
    _ = register_temp_concept(care, 430, 410, 2, ["care", "listening"])
    _ = register_temp_concept(assertive, 450, 410, 2, ["assertive"])

    Concept.stimulate(conflict, 1.0)

    care_multiplier = EmotionalBias.strength_multiplier(care)
    assertive_multiplier = EmotionalBias.strength_multiplier(assertive)

    assert care_multiplier >= 1.0
    assert assertive_multiplier <= 1.0
    assert care_multiplier > assertive_multiplier
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

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_emotional_bias_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end
end
