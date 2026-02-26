defmodule Wetware.Cell do
  alias Wetware.Util
  @moduledoc """
  A single sparse cell in the gel substrate.
  """

  use GenServer

  alias Wetware.{Params, Util}

  defstruct [
    :x,
    :y,
    kind: :interstitial,
    owners: [],
    charge: 0.0,
    valence: 0.0,
    neighbors: %{},
    params: %Params{},
    step_epoch: 0,
    last_step: 0,
    last_active_step: 0
  ]

  @type t :: %__MODULE__{}

  def child_spec(opts) do
    %{
      id: {__MODULE__, {Keyword.fetch!(opts, :x), Keyword.fetch!(opts, :y)}},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  def start_link(opts) do
    x = Keyword.fetch!(opts, :x)
    y = Keyword.fetch!(opts, :y)
    params = Keyword.get(opts, :params, Params.default())
    kind = Keyword.get(opts, :kind, :interstitial)
    owners = Keyword.get(opts, :owners, [])
    step_count = Keyword.get(opts, :step_count, 0)
    GenServer.start_link(__MODULE__, {x, y, params, kind, owners, step_count}, name: via(x, y))
  end

  def via(x, y), do: {:via, Registry, {Wetware.CellRegistry, {x, y}}}

  def stimulate(pid, amount) when is_pid(pid), do: GenServer.cast(pid, {:stimulate, amount})
  def stimulate({x, y}, amount), do: GenServer.cast(via(x, y), {:stimulate, amount})

  def set_charge(pid, charge) when is_pid(pid), do: GenServer.cast(pid, {:set_charge, charge})
  def set_charge({x, y}, charge), do: GenServer.cast(via(x, y), {:set_charge, charge})

  @doc """
  Async blend: pull cell's charge toward `target` by `factor`.
  Result: factor * target + (1 - factor) * current_charge.
  No read needed — the cell blends internally. Fire-and-forget.
  """
  def anchor_charge(pid, target, factor) when is_pid(pid),
    do: GenServer.cast(pid, {:anchor_charge, target, factor})
  def anchor_charge({x, y}, target, factor),
    do: GenServer.cast(via(x, y), {:anchor_charge, target, factor})

  @doc "Blend charge toward a target: charge = factor * target + (1 - factor) * charge"
  def blend_toward(pid, target, factor) when is_pid(pid),
    do: GenServer.cast(pid, {:blend_toward, target, factor})
  def blend_toward({x, y}, target, factor),
    do: GenServer.cast(via(x, y), {:blend_toward, target, factor})

  def stimulate_emotional(pid, amount, valence) when is_pid(pid) do
    GenServer.cast(pid, {:stimulate, amount, valence})
  end

  def stimulate_emotional({x, y}, amount, valence) do
    GenServer.cast(via(x, y), {:stimulate, amount, valence})
  end

  def step_with_charges(pid, neighbor_charges, step_count) when is_pid(pid) do
    step_with_charges(pid, neighbor_charges, %{}, step_count)
  end

  def step_with_charges({x, y}, neighbor_charges, step_count) do
    step_with_charges({x, y}, neighbor_charges, %{}, step_count)
  end

  def step_with_charges(pid, neighbor_charges, neighbor_valences, step_count) when is_pid(pid) do
    GenServer.call(
      pid,
      {:step_with_charges, neighbor_charges, neighbor_valences, step_count},
      15_000
    )
  end

  def step_with_charges({x, y}, neighbor_charges, neighbor_valences, step_count) do
    GenServer.call(
      via(x, y),
      {:step_with_charges, neighbor_charges, neighbor_valences, step_count},
      15_000
    )
  end

  def get_charge(pid) when is_pid(pid), do: GenServer.call(pid, :get_charge, 5_000)
  def get_charge({x, y}), do: GenServer.call(via(x, y), :get_charge, 5_000)

  def get_state(pid) when is_pid(pid), do: GenServer.call(pid, :get_state)
  def get_state({x, y}), do: GenServer.call(via(x, y), :get_state)

  def restore(target, charge, weights_map, attrs \\ [])

  def restore(pid, charge, weights_map, attrs) when is_pid(pid) do
    GenServer.call(pid, {:restore, charge, weights_map, attrs})
  end

  def restore({x, y}, charge, weights_map, attrs) do
    GenServer.call(via(x, y), {:restore, charge, weights_map, attrs})
  end

  def connect_neighbor(pid, {dx, dy}) when is_pid(pid),
    do: GenServer.call(pid, {:connect_neighbor, {dx, dy}})

  def add_owner(pid, owner) when is_pid(pid), do: GenServer.call(pid, {:add_owner, owner})

  @impl true
  def init({x, y, params, kind, owners, step_count}) do
    {:ok,
     %__MODULE__{
       x: x,
       y: y,
       params: params,
       kind: kind,
       owners: owners,
       last_step: step_count,
       last_active_step: step_count
     }}
  end

  @impl true
  def handle_cast({:stimulate, amount}, state) do
    {:noreply, stimulate_state(state, amount, 0.0)}
  end

  def handle_cast({:stimulate, amount, valence}, state) do
    {:noreply, stimulate_state(state, amount, valence)}
  end

  def handle_cast({:set_charge, charge}, state) do
    {:noreply, %{state | charge: Util.clamp(charge, 0.0, 1.0)}}
  end

  def handle_cast({:anchor_charge, target, factor}, state) do
    blended = factor * target + (1.0 - factor) * state.charge
    {:noreply, %{state | charge: Util.clamp(blended, 0.0, 1.0)}}
  end

  def handle_cast({:blend_toward, target, factor}, state) do
    blended = factor * target + (1.0 - factor) * state.charge
    {:noreply, %{state | charge: Util.clamp(blended, 0.0, 1.0)}}
  end

  @impl true
  def handle_call({:connect_neighbor, offset}, _from, state) do
    neighbors =
      Map.put_new(state.neighbors, offset, %{weight: state.params.w_init, crystallized: false})

    {:reply, :ok, %{state | neighbors: neighbors}}
  end

  def handle_call({:add_owner, owner}, _from, state) do
    owners = [owner | state.owners] |> Enum.uniq()
    kind = if owners == [], do: state.kind, else: :concept
    {:reply, :ok, %{state | owners: owners, kind: kind}}
  end

  def handle_call(
        {:step_with_charges, neighbor_charges, neighbor_valences, step_count},
        _from,
        state
      ) do
    new_state = do_step(state, neighbor_charges, neighbor_valences, step_count)
    {:reply, :ok, new_state}
  end

  def handle_call({:step_with_charges, neighbor_charges, step_count}, _from, state) do
    new_state = do_step(state, neighbor_charges, %{}, step_count)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_charge, _from, state), do: {:reply, state.charge, state}

  def handle_call(:get_state, _from, state) do
    reply = %{
      x: state.x,
      y: state.y,
      charge: state.charge,
      valence: state.valence,
      kind: state.kind,
      owners: state.owners,
      neighbors: state.neighbors,
      step_epoch: state.step_epoch,
      last_step: state.last_step,
      last_active_step: state.last_active_step
    }

    {:reply, reply, state}
  end

  def handle_call({:restore, charge, weights_map, attrs}, _from, state) do
    neighbors =
      if map_size(weights_map) == 0 do
        state.neighbors
      else
        weights_map
        |> Enum.map(fn {offset, entry} ->
          {offset,
           %{
             weight: Map.get(entry, :weight, Map.get(entry, "weight", state.params.w_init)),
             crystallized: Map.get(entry, :crystallized, Map.get(entry, "crystallized", false))
           }}
        end)
        |> Map.new()
      end

    kind = Keyword.get(attrs, :kind, state.kind)
    owners = Keyword.get(attrs, :owners, state.owners)
    valence = Util.clamp(Keyword.get(attrs, :valence, state.valence), -1.0, 1.0)
    last_step = Keyword.get(attrs, :last_step, state.last_step)
    last_active_step = Keyword.get(attrs, :last_active_step, state.last_active_step)

    {:reply, :ok,
     %{
       state
       | charge: charge,
         valence: valence,
         neighbors: neighbors,
         kind: kind,
         owners: owners,
         last_step: last_step,
         last_active_step: last_active_step
     }}
  end

  defp do_step(state, neighbor_charges, neighbor_valences, step_count) do
    p = state.params
    profile = kind_profile(state.kind)

    # CFL stability clamp: prevent overshoot when total effective coupling
    # exceeds the stability bound for explicit Euler diffusion.
    # With 8 neighbors and crystallized weights near w_max=1.0,
    # unclamped coupling = 8 * 1.0 * 0.12 = 0.96 — this caused the
    # period-2 oscillation discovered in S~421.
    #
    # Clamped at 0.15: prevents oscillation (any value < 0.5 works) while
    # preserving meaningful charge differentiation across dream steps.
    # At 0.15 per step, 20 dream steps retain ~4% of initial differentiation —
    # combined with random stimulation, this produces gentle mixing with
    # structure rather than uniform convergence.
    stability_max = 0.15
    base_rate = p.propagation_rate * profile.propagation_mult

    total_coupling =
      Enum.reduce(state.neighbors, 0.0, fn {_offset, %{weight: weight}}, acc ->
        acc + weight * base_rate
      end)

    stability_factor = if total_coupling > stability_max, do: stability_max / total_coupling, else: 1.0

    propagated_charge =
      Enum.reduce(state.neighbors, 0.0, fn {offset, %{weight: weight}}, acc ->
        neighbor_charge = Map.get(neighbor_charges, offset, 0.0)

        flow =
          (neighbor_charge - state.charge) * weight * base_rate * stability_factor

        acc + flow
      end)

    valence_total_coupling =
      Enum.reduce(state.neighbors, 0.0, fn {_offset, %{weight: weight}}, acc ->
        acc + weight * p.valence_propagation_rate
      end)

    valence_stability = if valence_total_coupling > 0.5, do: 0.5 / valence_total_coupling, else: 1.0

    propagated_valence =
      Enum.reduce(state.neighbors, 0.0, fn {offset, %{weight: weight}}, acc ->
        neighbor_valence = Map.get(neighbor_valences, offset, 0.0)
        flow = (neighbor_valence - state.valence) * weight * p.valence_propagation_rate * valence_stability
        acc + flow
      end)

    new_charge = Util.clamp(state.charge + propagated_charge, 0.0, 1.0)
    new_valence = Util.clamp(state.valence + propagated_valence, -1.0, 1.0)
    am_active = new_charge > p.activation_threshold

    neighbors =
      Map.new(state.neighbors, fn {offset, %{weight: weight, crystallized: crystallized}} ->
        neighbor_charge = Map.get(neighbor_charges, offset, 0.0)
        neighbor_active = neighbor_charge > p.activation_threshold

        weight =
          if am_active and neighbor_active do
            min(weight + p.learning_rate * profile.learning_mult, p.w_max)
          else
            weight
          end

        crystallized = crystallized or weight >= p.crystal_threshold

        decay =
          if crystallized do
            p.decay_rate * p.crystal_decay_factor * profile.weight_decay_mult
          else
            p.decay_rate * profile.weight_decay_mult
          end

        new_weight = max(weight - decay, p.w_min)
        {offset, %{weight: new_weight, crystallized: crystallized}}
      end)

    charge_decay = min(p.charge_decay * profile.charge_decay_mult, 0.95)
    decayed_charge = Util.clamp(new_charge * (1.0 - charge_decay), 0.0, 1.0)
    decayed_valence = Util.clamp(new_valence * (1.0 - min(p.valence_decay, 0.95)), -1.0, 1.0)

    last_active_step =
      if decayed_charge > p.activation_threshold do
        step_count
      else
        state.last_active_step
      end

    %{
      state
      | charge: decayed_charge,
        valence: decayed_valence,
        neighbors: neighbors,
        step_epoch: state.step_epoch + 1,
        last_step: step_count,
        last_active_step: last_active_step
    }
  end

  defp kind_profile(:concept) do
    %{propagation_mult: 1.0, charge_decay_mult: 0.7, learning_mult: 1.1, weight_decay_mult: 0.8}
  end

  defp kind_profile(:axon) do
    %{propagation_mult: 1.6, charge_decay_mult: 0.5, learning_mult: 0.8, weight_decay_mult: 0.6}
  end

  defp kind_profile(:interstitial) do
    %{propagation_mult: 0.6, charge_decay_mult: 1.5, learning_mult: 0.6, weight_decay_mult: 1.4}
  end

  defp kind_profile(_) do
    %{propagation_mult: 1.0, charge_decay_mult: 1.0, learning_mult: 1.0, weight_decay_mult: 1.0}
  end

  defp stimulate_state(state, amount, valence) do
    new_charge = Util.clamp(state.charge + amount, 0.0, 1.0)
    new_valence = Util.clamp(state.valence + valence * amount, -1.0, 1.0)

    if new_charge > state.params.activation_threshold do
      %{
        state
        | charge: new_charge,
          valence: new_valence,
          last_active_step: max(state.last_active_step, state.last_step)
      }
    else
      %{state | charge: new_charge, valence: new_valence}
    end
  end
end
