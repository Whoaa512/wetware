defmodule Wetware.Cell do
  @moduledoc """
  A single cell in the gel substrate.

  Each cell is a GenServer process — a living piece of wetware.
  It has charge, connections to neighbors with evolving weights,
  and can crystallize connections that are used enough.

  BEAM processes ARE the substrate. Message passing IS propagation.
  """

  use GenServer

  alias Wetware.Params

  defstruct [
    :x, :y,
    charge: 0.0,
    neighbors: %{},       # %{{dx, dy} => {pid, weight, crystallized}}
    params: %Params{},
    step_epoch: 0
  ]

  @type neighbor_info :: {pid(), float(), boolean()}
  @type t :: %__MODULE__{
    x: non_neg_integer(),
    y: non_neg_integer(),
    charge: float(),
    neighbors: %{optional({integer(), integer()}) => neighbor_info()},
    params: Params.t(),
    step_epoch: non_neg_integer()
  }

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts) do
    x = Keyword.fetch!(opts, :x)
    y = Keyword.fetch!(opts, :y)
    params = Keyword.get(opts, :params, Params.default())
    name = via(x, y)
    GenServer.start_link(__MODULE__, {x, y, params}, name: name)
  end

  @doc "Registry via-tuple for a cell at (x, y)."
  def via(x, y), do: {:via, Registry, {Wetware.CellRegistry, {x, y}}}

  @doc "Inject charge into this cell."
  def stimulate(pid, amount) when is_pid(pid) do
    GenServer.cast(pid, {:stimulate, amount})
  end

  def stimulate({x, y}, amount) do
    GenServer.cast(via(x, y), {:stimulate, amount})
  end

  @doc "Set neighbors after all cells are started."
  def set_neighbors(pid, neighbors) when is_pid(pid) do
    GenServer.call(pid, {:set_neighbors, neighbors})
  end

  def set_neighbors({x, y}, neighbors) do
    GenServer.call(via(x, y), {:set_neighbors, neighbors})
  end

  @doc """
  Execute one physics step with pre-collected neighbor charges.
  neighbor_charges is %{{dx, dy} => charge_value}
  This avoids cells calling each other during step (no deadlocks).
  """
  def step_with_charges(pid, neighbor_charges) when is_pid(pid) do
    GenServer.call(pid, {:step_with_charges, neighbor_charges}, 15_000)
  end

  def step_with_charges({x, y}, neighbor_charges) do
    GenServer.call(via(x, y), {:step_with_charges, neighbor_charges}, 15_000)
  end

  @doc "Get current charge only (lightweight)."
  def get_charge(pid) when is_pid(pid) do
    GenServer.call(pid, :get_charge, 5_000)
  end

  def get_charge({x, y}) do
    GenServer.call(via(x, y), :get_charge, 5_000)
  end

  @doc "Get current cell state."
  def get_state(pid) when is_pid(pid) do
    GenServer.call(pid, :get_state)
  end

  def get_state({x, y}) do
    GenServer.call(via(x, y), :get_state)
  end

  @doc "Restore cell state from saved data."
  def restore(pid, charge, weights_map) when is_pid(pid) do
    GenServer.call(pid, {:restore, charge, weights_map})
  end

  def restore({x, y}, charge, weights_map) do
    GenServer.call(via(x, y), {:restore, charge, weights_map})
  end

  # ── Server Callbacks ───────────────────────────────────────

  @impl true
  def init({x, y, params}) do
    {:ok, %__MODULE__{x: x, y: y, params: params}}
  end

  @impl true
  def handle_cast({:stimulate, amount}, state) do
    new_charge = clamp(state.charge + amount, 0.0, 1.0)
    {:noreply, %{state | charge: new_charge}}
  end

  @impl true
  def handle_call({:set_neighbors, neighbor_pids}, _from, state) do
    neighbors =
      Map.new(neighbor_pids, fn {offset, pid} ->
        {offset, {pid, state.params.w_init, false}}
      end)

    {:reply, :ok, %{state | neighbors: neighbors}}
  end

  def handle_call({:step_with_charges, neighbor_charges}, _from, state) do
    new_state = do_step(state, neighbor_charges)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_charge, _from, state) do
    {:reply, state.charge, state}
  end

  def handle_call(:get_state, _from, state) do
    reply = %{
      x: state.x,
      y: state.y,
      charge: state.charge,
      neighbors:
        Map.new(state.neighbors, fn {offset, {_pid, weight, cryst}} ->
          {offset, %{weight: weight, crystallized: cryst}}
        end),
      step_epoch: state.step_epoch
    }

    {:reply, reply, state}
  end

  def handle_call({:restore, charge, weights_map}, _from, state) do
    neighbors =
      Map.new(state.neighbors, fn {offset, {pid, _w, _c}} ->
        case Map.get(weights_map, offset) do
          nil -> {offset, {pid, state.params.w_init, false}}
          %{weight: w, crystallized: c} -> {offset, {pid, w, c}}
        end
      end)

    {:reply, :ok, %{state | charge: charge, neighbors: neighbors}}
  end

  # ── Physics Engine ──────────────────────────────────────────

  defp do_step(state, neighbor_charges) do
    p = state.params

    # 1. Charge propagation
    propagated_charge =
      Enum.reduce(state.neighbors, 0.0, fn {offset, {_pid, weight, _cryst}}, acc ->
        neighbor_charge = Map.get(neighbor_charges, offset, 0.0)
        flow = (neighbor_charge - state.charge) * weight * p.propagation_rate
        acc + flow
      end)

    new_charge = clamp(state.charge + propagated_charge, 0.0, 1.0)

    # 2. Hebbian learning
    am_active = new_charge > p.activation_threshold

    neighbors =
      Map.new(state.neighbors, fn {offset, {pid, weight, crystallized}} ->
        neighbor_charge = Map.get(neighbor_charges, offset, 0.0)
        neighbor_active = neighbor_charge > p.activation_threshold

        weight =
          if am_active and neighbor_active do
            min(weight + p.learning_rate, p.w_max)
          else
            weight
          end

        crystallized = crystallized or weight >= p.crystal_threshold

        {offset, {pid, weight, crystallized}}
      end)

    # 3. Decay
    decayed_charge = new_charge * (1.0 - p.charge_decay)

    neighbors =
      Map.new(neighbors, fn {offset, {pid, weight, crystallized}} ->
        decay =
          if crystallized do
            p.decay_rate * p.crystal_decay_factor
          else
            p.decay_rate
          end

        new_weight = max(weight - decay, p.w_min)
        {offset, {pid, new_weight, crystallized}}
      end)

    %{state |
      charge: clamp(decayed_charge, 0.0, 1.0),
      neighbors: neighbors,
      step_epoch: state.step_epoch + 1
    }
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))
end
