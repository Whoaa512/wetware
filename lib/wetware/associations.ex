defmodule Wetware.Associations do
  @moduledoc """
  Tracks co-activation associations between concepts.

  When concepts are stimulated together (same imprint), their association
  strengthens via Hebbian learning. Associations decay over time.

  This is the semantic layer — spatial gel handles local propagation,
  this module handles long-range concept-to-concept wiring.
  """

  use GenServer

  @learning_rate 0.05    # How fast co-activation strengthens associations
  @decay_rate 0.003      # How fast associations weaken per step
  @min_weight 0.0
  @max_weight 1.0

  # ── Client API ──────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Record co-activation of a set of concepts."
  def co_activate(concept_names) when is_list(concept_names) do
    GenServer.cast(__MODULE__, {:co_activate, concept_names})
  end

  @doc "Decay all associations by one step."
  def decay_step do
    GenServer.cast(__MODULE__, :decay_step)
  end

  @doc "Decay all associations by n steps."
  def decay(n) when is_integer(n) and n > 0 do
    Enum.each(1..n, fn _ -> decay_step() end)
  end

  @doc "Get top associations for a concept."
  def get(concept_name, top_n \\ 10) do
    GenServer.call(__MODULE__, {:get, concept_name, top_n})
  end

  @doc "Get all associations above a threshold."
  def all(min_weight \\ 0.05) do
    GenServer.call(__MODULE__, {:all, min_weight})
  end

  @doc "Export state as a serializable map."
  def export do
    GenServer.call(__MODULE__, :export)
  end

  @doc "Import state from a map."
  def import(state) do
    GenServer.call(__MODULE__, {:import, state})
  end

  # ── Server ──────────────────────────────────────────────────

  @impl true
  def init(_) do
    {:ok, %{weights: %{}}}
  end

  @impl true
  def handle_cast({:co_activate, names}, state) do
    names = Enum.uniq(names)

    # For every pair, strengthen the association
    new_weights =
      Enum.reduce(pairs(names), state.weights, fn {a, b}, acc ->
        key = pair_key(a, b)
        current = Map.get(acc, key, 0.0)
        # Hebbian: strengthen proportional to how far from max
        delta = @learning_rate * (1.0 - current)
        Map.put(acc, key, min(current + delta, @max_weight))
      end)

    {:noreply, %{state | weights: new_weights}}
  end

  @impl true
  def handle_cast(:decay_step, state) do
    new_weights =
      state.weights
      |> Enum.map(fn {key, w} ->
        new_w = w - @decay_rate
        {key, max(new_w, @min_weight)}
      end)
      |> Enum.reject(fn {_key, w} -> w <= @min_weight end)
      |> Map.new()

    {:noreply, %{state | weights: new_weights}}
  end

  @impl true
  def handle_call({:get, name, top_n}, _from, state) do
    assocs =
      state.weights
      |> Enum.filter(fn {{a, b}, _w} -> a == name or b == name end)
      |> Enum.map(fn {{a, b}, w} ->
        other = if a == name, do: b, else: a
        {other, Float.round(w, 4)}
      end)
      |> Enum.sort_by(fn {_, w} -> -w end)
      |> Enum.take(top_n)

    {:reply, assocs, state}
  end

  @impl true
  def handle_call({:all, min_weight}, _from, state) do
    assocs =
      state.weights
      |> Enum.filter(fn {_key, w} -> w >= min_weight end)
      |> Enum.map(fn {{a, b}, w} -> {a, b, Float.round(w, 4)} end)
      |> Enum.sort_by(fn {_, _, w} -> -w end)

    {:reply, assocs, state}
  end

  @impl true
  def handle_call(:export, _from, state) do
    # Convert tuple keys to string keys for JSON serialization
    serializable =
      state.weights
      |> Enum.map(fn {{a, b}, w} -> {"#{a}|#{b}", w} end)
      |> Map.new()

    {:reply, serializable, state}
  end

  @impl true
  def handle_call({:import, data}, _from, _state) do
    weights =
      data
      |> Enum.map(fn {key, w} ->
        [a, b] = String.split(key, "|", parts: 2)
        {pair_key(a, b), w}
      end)
      |> Map.new()

    {:reply, :ok, %{weights: weights}}
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp pair_key(a, b) when a <= b, do: {a, b}
  defp pair_key(a, b), do: {b, a}

  defp pairs([]), do: []
  defp pairs([_]), do: []
  defp pairs(list) do
    for i <- 0..(length(list) - 2),
        j <- (i + 1)..(length(list) - 1) do
      {Enum.at(list, i), Enum.at(list, j)}
    end
  end
end
