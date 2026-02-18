defmodule Wetware.AutoImprintTest do
  use ExUnit.Case, async: false

  alias Wetware.{AutoImprint, Concept, Persistence, Resonance}

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  setup do
    baseline_path = tmp_path("auto_imprint_baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm(baseline_path)
    end)

    :ok
  end

  test "auto-imprint extracts known concepts and applies weighted imprint" do
    before_charge = Concept.charge("coding")

    text =
      "We had a tough conflict while coding but made a breakthrough and progress by listening."

    assert {:ok, result} = AutoImprint.run(text, duration_minutes: 120, depth: 8)
    assert result.weight > 1.0
    assert result.steps >= 3
    assert is_list(result.matched_concepts)

    assert Enum.any?(result.matched_concepts, fn {name, _count, _strength} -> name == "coding" end)

    assert Concept.charge("coding") > before_charge
  end

  test "auto-imprint returns no-match error when transcript has no known concepts" do
    assert {:error, :no_concepts_matched} =
             AutoImprint.run("xqv zzt lmnqv unslotted phrasing", depth: 3, duration_minutes: 10)
  end

  test "depth/duration weighting scales stronger for deeper longer sessions" do
    shallow = AutoImprint.depth_duration_weight(1, 5)
    medium = AutoImprint.depth_duration_weight(5, 30)
    deep = AutoImprint.depth_duration_weight(9, 120)

    assert shallow < medium
    assert medium < deep
  end

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "wetware_auto_imprint_test_#{label}_#{System.unique_integer([:positive, :monotonic])}.json"
    )
  end
end
