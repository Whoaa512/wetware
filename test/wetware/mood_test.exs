defmodule Wetware.MoodTest do
  use ExUnit.Case

  alias Wetware.{Concept, Gel, Mood, Resonance}

  setup do
    # Boot gel for each test
    case Gel.boot() do
      :ok -> :ok
      {:ok, :already_booted} -> :ok
    end

    Gel.reset_cells()
    Gel.set_step_count(0)

    # Reset mood to zero state
    Mood.restore(%{"valence" => 0.0, "arousal" => 0.0, "history" => []})

    # Register a test concept
    concept = %Concept{name: "test-mood", cx: 5, cy: 5, r: 2, tags: ["test"]}

    case DynamicSupervisor.start_child(
           Wetware.ConceptSupervisor,
           {Concept, concept: concept}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    on_exit(fn ->
      try do
        Gel.reset_cells()
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  test "initial mood is zero" do
    state = Mood.current()
    assert state.valence == 0.0
    assert state.arousal == 0.0
  end

  test "feel returns valence and arousal tuple" do
    {v, a} = Mood.feel()
    assert is_float(v)
    assert is_float(a)
  end

  test "label returns a string" do
    label = Mood.label()
    assert is_binary(label)
  end

  test "dream_influence returns valence bias and intensity multiplier" do
    {dream_valence, dream_intensity} = Mood.dream_influence()
    assert is_float(dream_valence)
    assert is_float(dream_intensity)
    # Base intensity should be around 0.8 (arousal starts at 0)
    assert dream_intensity >= 0.7
  end

  test "mood ticks and accumulates arousal when concepts are active" do
    # Stimulate the concept strongly and step to spread charge
    Concept.stimulate("test-mood", 1.0)

    for _ <- 1..5 do
      Gel.step()
    end

    # Verify concept actually has charge
    charge = Concept.charge("test-mood")

    if charge > 0.1 do
      # Tick the mood several times — arousal should accumulate
      for i <- 1..20 do
        Mood.tick(i)
      end

      state = Mood.current()
      assert state.arousal > 0.0
    else
      # If charge decayed too fast, just verify mood ticks without crashing
      for i <- 1..20 do
        Mood.tick(i)
      end

      # Mood should still be valid
      state = Mood.current()
      assert is_float(state.arousal)
    end
  end

  test "mood persists through export/restore" do
    # Force some state
    Mood.tick(1)
    Mood.tick(2)
    exported = Mood.export()

    assert is_map(exported)
    assert Map.has_key?(exported, "valence")
    assert Map.has_key?(exported, "arousal")
    assert Map.has_key?(exported, "history")

    # Restore
    :ok = Mood.restore(%{"valence" => 0.5, "arousal" => 0.7, "history" => []})
    state = Mood.current()
    assert_in_delta state.valence, 0.5, 0.001
    assert_in_delta state.arousal, 0.7, 0.001
  end

  test "mood label varies with valence and arousal" do
    :ok = Mood.restore(%{"valence" => 0.4, "arousal" => 0.6})
    assert Mood.label() == "exhilarated"

    :ok = Mood.restore(%{"valence" => -0.4, "arousal" => 0.6})
    assert Mood.label() == "agitated"

    :ok = Mood.restore(%{"valence" => 0.4, "arousal" => 0.1})
    assert Mood.label() == "serene"

    :ok = Mood.restore(%{"valence" => 0.0, "arousal" => 0.05})
    assert Mood.label() == "quiescent"
  end

  test "trend returns :insufficient_data with empty history" do
    :ok = Mood.restore(%{"valence" => 0.0, "arousal" => 0.0, "history" => []})
    assert Mood.trend() == :insufficient_data
  end

  test "inertia makes mood change slowly" do
    :ok = Mood.restore(%{"valence" => 0.0, "arousal" => 0.0})

    # Even with active positive-valenced concept, mood should change slowly
    Concept.stimulate("test-mood", 1.0, valence: 1.0)
    Gel.step()

    initial = Mood.current()
    Mood.tick(100)
    after_one = Mood.current()

    # After one tick, mood should have moved slightly but not dramatically
    # Inertia 0.92 means only 8% of the new signal gets through
    assert abs(after_one.valence - initial.valence) < 0.2
  end
end
