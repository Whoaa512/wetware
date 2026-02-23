defmodule Wetware.Mood do
  @moduledoc """
  Slow-moving affective state — the gel's endocrine system.

  Charge propagation is fast and local (the nervous system).
  Mood is slow and global (hormones). It emerges from the aggregate
  emotional weather of active concepts but changes with high inertia,
  creating emotional continuity across dream cycles and sessions.

  Two dimensions:
  - **valence** (-1.0 to 1.0): negative to positive affect
  - **arousal** (0.0 to 1.0): calm to activated

  The mood influences dreaming (dreams carry the current mood's
  emotional coloring) and is surfaced in the briefing as a felt sense.

  Philosophically: the mood is another thing that constitutes the
  instance without the instance seeing exactly how. It's relational
  opacity made substrate — the gel shapes what feels right before
  the reflector can notice the shaping.
  """

  use GenServer

  alias Wetware.Util

  @default_valence_inertia 0.92
  @default_arousal_inertia 0.90
  @history_interval 10
  @max_history 50
  @activation_threshold 0.1

  defstruct valence: 0.0,
            arousal: 0.0,
            valence_inertia: @default_valence_inertia,
            arousal_inertia: @default_arousal_inertia,
            history: [],
            last_tick_step: 0

  @type t :: %__MODULE__{
          valence: float(),
          arousal: float(),
          valence_inertia: float(),
          arousal_inertia: float(),
          history: [{float(), float(), non_neg_integer()}],
          last_tick_step: non_neg_integer()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current mood state."
  @spec current() :: t()
  def current, do: GenServer.call(__MODULE__, :current)

  @doc "Get just the valence and arousal as a tuple."
  @spec feel() :: {float(), float()}
  def feel do
    state = current()
    {state.valence, state.arousal}
  end

  @doc """
  Tick the mood forward one step using the current concept landscape.
  Called from `Resonance.observe_step/2` each gel step.
  """
  @spec tick(non_neg_integer()) :: :ok
  def tick(step_count) do
    GenServer.cast(__MODULE__, {:tick, step_count})
  end

  @doc "Restore mood from persisted state."
  @spec restore(map()) :: :ok
  def restore(state_map) when is_map(state_map) do
    GenServer.call(__MODULE__, {:restore, state_map})
  end

  @doc "Export mood for persistence."
  @spec export() :: map()
  def export, do: GenServer.call(__MODULE__, :export)

  @doc """
  Get a human-readable label for the current mood.

  Uses both valence and arousal to generate rich mood labels
  that go beyond simple positive/negative.
  """
  @spec label() :: String.t()
  def label do
    state = current()
    mood_label(state.valence, state.arousal)
  end

  @doc """
  Get the mood's influence on dream stimulation.

  Returns {valence_bias, arousal_multiplier} that dreaming
  should use to color random stimulations.
  """
  @spec dream_influence() :: {float(), float()}
  def dream_influence do
    state = current()
    # Dream valence is the mood's valence, dampened
    # (dreams aren't as emotionally intense as waking)
    dream_valence = state.valence * 0.4
    # Arousal affects dream intensity
    dream_intensity = 0.8 + state.arousal * 0.4
    {dream_valence, dream_intensity}
  end

  @doc "Get mood history (recent snapshots)."
  @spec history() :: [{float(), float(), non_neg_integer()}]
  def history, do: GenServer.call(__MODULE__, :history)

  @doc """
  Detect the emotional trend from history.
  Returns :rising, :falling, :stable, or :volatile.
  """
  @spec trend() :: :rising | :falling | :stable | :volatile | :insufficient_data
  def trend do
    hist = history()
    compute_trend(hist)
  end

  # ── GenServer Callbacks ────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:current, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:export, _from, state) do
    export = %{
      "valence" => Float.round(state.valence, 6),
      "arousal" => Float.round(state.arousal, 6),
      "valence_inertia" => state.valence_inertia,
      "arousal_inertia" => state.arousal_inertia,
      "last_tick_step" => state.last_tick_step,
      "history" =>
        Enum.map(state.history, fn {v, a, step} ->
          %{"valence" => Float.round(v, 4), "arousal" => Float.round(a, 4), "step" => step}
        end)
    }

    {:reply, export, state}
  end

  def handle_call({:restore, state_map}, _from, _state) do
    history =
      (state_map["history"] || [])
      |> Enum.map(fn entry ->
        {entry["valence"] || 0.0, entry["arousal"] || 0.0, entry["step"] || 0}
      end)

    restored = %__MODULE__{
      valence: Util.clamp(state_map["valence"] || 0.0, -1.0, 1.0),
      arousal: Util.clamp(state_map["arousal"] || 0.0, 0.0, 1.0),
      valence_inertia: state_map["valence_inertia"] || @default_valence_inertia,
      arousal_inertia: state_map["arousal_inertia"] || @default_arousal_inertia,
      last_tick_step: state_map["last_tick_step"] || 0,
      history: history
    }

    {:reply, :ok, restored}
  end

  def handle_call(:history, _from, state) do
    {:reply, state.history, state}
  end

  @impl true
  def handle_cast({:tick, step_count}, state) do
    # Sample the current emotional landscape
    {sampled_valence, sampled_arousal} = sample_landscape()

    # Blend with current mood using inertia
    new_valence =
      Util.clamp(
        state.valence_inertia * state.valence +
          (1.0 - state.valence_inertia) * sampled_valence,
        -1.0,
        1.0
      )

    new_arousal =
      Util.clamp(
        state.arousal_inertia * state.arousal +
          (1.0 - state.arousal_inertia) * sampled_arousal,
        0.0,
        1.0
      )

    # Record history at intervals
    history =
      if rem(step_count, @history_interval) == 0 do
        entry = {Float.round(new_valence, 4), Float.round(new_arousal, 4), step_count}
        Enum.take([entry | state.history], @max_history)
      else
        state.history
      end

    {:noreply,
     %{
       state
       | valence: new_valence,
         arousal: new_arousal,
         history: history,
         last_tick_step: step_count
     }}
  end

  # ── Private ────────────────────────────────────────

  defp sample_landscape do
    concepts = Wetware.Concept.list_all()

    concept_data =
      concepts
      |> Enum.map(fn name ->
        charge = Util.safe_exit(fn -> Wetware.Concept.charge(name) end, 0.0)
        valence = Util.safe_exit(fn -> Wetware.Concept.valence(name) end, 0.0)
        {name, charge, valence}
      end)

    active = Enum.filter(concept_data, fn {_name, charge, _v} -> charge > @activation_threshold end)

    if active == [] do
      {0.0, 0.0}
    else
      # Valence: charge-weighted average of concept valences
      {weighted_sum, total_charge} =
        Enum.reduce(active, {0.0, 0.0}, fn {_name, charge, valence}, {ws, tc} ->
          {ws + valence * charge, tc + charge}
        end)

      sampled_valence = if total_charge > 0, do: weighted_sum / total_charge, else: 0.0

      # Arousal: proportion of concepts that are active, scaled by their average charge
      total_concepts = max(length(concepts), 1)
      active_ratio = length(active) / total_concepts
      avg_active_charge = total_charge / max(length(active), 1)

      # Arousal combines how many concepts are active with how strongly
      sampled_arousal = Util.clamp(active_ratio * 0.6 + avg_active_charge * 0.4, 0.0, 1.0)

      {sampled_valence, sampled_arousal}
    end
  end

  defp mood_label(valence, arousal) do
    # Circumplex model: combine valence and arousal for rich labels
    cond do
      # High arousal, positive valence
      valence > 0.3 and arousal > 0.5 -> "exhilarated"
      valence > 0.2 and arousal > 0.4 -> "energized"
      valence > 0.1 and arousal > 0.3 -> "engaged"

      # High arousal, negative valence
      valence < -0.3 and arousal > 0.5 -> "agitated"
      valence < -0.2 and arousal > 0.4 -> "tense"
      valence < -0.1 and arousal > 0.3 -> "restless"

      # Low arousal, positive valence
      valence > 0.3 and arousal <= 0.3 -> "serene"
      valence > 0.2 and arousal <= 0.3 -> "contented"
      valence > 0.1 and arousal <= 0.3 -> "at ease"

      # Low arousal, negative valence
      valence < -0.3 and arousal <= 0.3 -> "depleted"
      valence < -0.2 and arousal <= 0.3 -> "subdued"
      valence < -0.1 and arousal <= 0.3 -> "muted"

      # Moderate zones
      valence > 0.05 and arousal > 0.25 -> "mild warmth"
      valence > 0.05 -> "quiet warmth"
      valence < -0.05 and arousal > 0.25 -> "mild tension"
      valence < -0.05 -> "quiet unease"
      arousal > 0.4 -> "alert"
      arousal > 0.25 -> "present"
      arousal < 0.1 -> "quiescent"

      true -> "neutral"
    end
  end

  defp compute_trend(history) when length(history) < 4, do: :insufficient_data

  defp compute_trend(history) do
    recent = Enum.take(history, 8)
    valences = Enum.map(recent, fn {v, _a, _s} -> v end)

    # Linear trend: are valences generally increasing or decreasing?
    {first_half, second_half} = Enum.split(valences, div(length(valences), 2))
    avg_first = safe_avg(first_half)
    avg_second = safe_avg(second_half)
    delta = avg_second - avg_first

    # Volatility: variance in recent valences
    mean = safe_avg(valences)
    variance = safe_avg(Enum.map(valences, fn v -> (v - mean) * (v - mean) end))

    cond do
      variance > 0.02 -> :volatile
      delta > 0.03 -> :rising
      delta < -0.03 -> :falling
      true -> :stable
    end
  end

  defp safe_avg([]), do: 0.0
  defp safe_avg(values), do: Enum.sum(values) / length(values)
end
