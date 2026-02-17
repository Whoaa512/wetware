defmodule Wetware.Gel do
  @moduledoc """
  Sparse, on-demand gel substrate.
  """

  use GenServer

  alias Wetware.{Cell, Params, Resonance}

  defstruct params: %Params{}, step_count: 0, started: false, concepts: %{}

  def start_link(opts \\ []) do
    params = Keyword.get(opts, :params, Params.default())
    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  def boot, do: GenServer.call(__MODULE__, :boot, 120_000)
  def booted?, do: GenServer.call(__MODULE__, :booted?)

  def step, do: GenServer.call(__MODULE__, :step, 60_000)

  def step(n) when is_integer(n) and n > 0 do
    Enum.each(1..n, fn _ -> step() end)
  end

  def ensure_cell(coord, reason \\ :manual, opts \\ []), do: GenServer.call(__MODULE__, {:ensure_cell, coord, reason, opts})
  def despawn_cell(coord), do: GenServer.call(__MODULE__, {:despawn_cell, coord})

  def register_concept(concept), do: GenServer.call(__MODULE__, {:register_concept, concept})
  def unregister_concept(name), do: GenServer.call(__MODULE__, {:unregister_concept, name})

  def concepts, do: GenServer.call(__MODULE__, :concepts)

  def concept_region(name), do: GenServer.call(__MODULE__, {:concept_region, name})

  def concept_cells(name), do: GenServer.call(__MODULE__, {:concept_cells, name})
  def set_concepts(concepts) when is_map(concepts), do: GenServer.call(__MODULE__, {:set_concepts, concepts})

  def bounds do
    case Wetware.Gel.Index.bounds() do
      nil -> %{min_x: 0, max_x: 0, min_y: 0, max_y: 0}
      b -> b
    end
  end

  def stimulate_region(cx, cy, radius, strength \\ 1.0) do
    GenServer.cast(__MODULE__, {:stimulate_region, cx, cy, radius, strength})
  end

  def get_charges, do: GenServer.call(__MODULE__, :get_charges, 60_000)

  def get_cell(x, y), do: Cell.get_state({x, y})

  def step_count, do: GenServer.call(__MODULE__, :step_count)
  def set_step_count(n) when is_integer(n) and n >= 0, do: GenServer.call(__MODULE__, {:set_step_count, n})
  def params, do: GenServer.call(__MODULE__, :params)
  def reset_cells, do: GenServer.call(__MODULE__, :reset_cells)

  @impl true
  def init(params) do
    {:ok, %__MODULE__{params: params}}
  end

  @impl true
  def handle_call(:boot, _from, %{started: true} = state), do: {:reply, {:ok, :already_booted}, state}

  def handle_call(:boot, _from, state), do: {:reply, :ok, %{state | started: true}}

  def handle_call(:booted?, _from, state), do: {:reply, state.started, state}

  def handle_call({:ensure_cell, coord, reason, opts}, _from, state) do
    {reply, new_state} = ensure_cell_impl(coord, reason, opts, state)
    {:reply, reply, new_state}
  end

  def handle_call({:despawn_cell, coord}, _from, state) do
    case Wetware.Gel.Index.cell_pid(coord) do
      {:ok, pid} ->
        snapshot_cell(coord, pid)
        Process.exit(pid, :normal)
        :ok = Wetware.Gel.Index.delete_cell(coord)
        {:reply, :ok, state}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:register_concept, concept}, _from, state) do
    name = concept.name
    tags = Map.get(concept, :tags, [])
    r = Map.get(concept, :r, 3)

    {cx, cy} =
      cond do
        is_integer(Map.get(concept, :cx)) and is_integer(Map.get(concept, :cy)) ->
          {concept.cx, concept.cy}

        true ->
          Wetware.Layout.Engine.place(name, tags, state.concepts)
      end

    info = %{center: {cx, cy}, r: r, tags: tags}

    coords =
      for y <- (cy - r)..(cy + r),
          x <- (cx - r)..(cx + r),
          (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r,
          do: {x, y}

    {_, post_seed_state} =
      Enum.reduce(coords, {{:ok, :seeded}, %{state | concepts: Map.put(state.concepts, name, info)}}, fn coord, {_, acc_state} ->
        {_result, next_state} = ensure_cell_impl(coord, :concept_seed, [kind: :concept, owner: name], acc_state)
        {{:ok, :seeded}, next_state}
      end)

    reply_concept = Map.merge(concept, %{cx: cx, cy: cy, r: r})
    {:reply, {:ok, reply_concept}, post_seed_state}
  end

  def handle_call({:unregister_concept, name}, _from, state) do
    {:reply, :ok, %{state | concepts: Map.delete(state.concepts, name)}}
  end

  def handle_call(:concepts, _from, state), do: {:reply, state.concepts, state}
  def handle_call({:set_concepts, concepts}, _from, state), do: {:reply, :ok, %{state | concepts: concepts}}

  def handle_call({:concept_region, name}, _from, state) do
    case Map.get(state.concepts, name) do
      nil -> {:reply, {:error, :not_found}, state}
      %{center: {cx, cy}, r: r, tags: tags} -> {:reply, %{name: name, cx: cx, cy: cy, r: r, tags: tags}, state}
    end
  end

  def handle_call({:concept_cells, name}, _from, state) do
    coords =
      case Map.get(state.concepts, name) do
        nil -> []
        %{center: {cx, cy}, r: r} ->
          for y <- (cy - r)..(cy + r),
              x <- (cx - r)..(cx + r),
              (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r,
              do: {x, y}
      end

    {:reply, coords, state}
  end

  def handle_call(:step, _from, %{started: false} = state), do: {:reply, {:error, :not_booted}, state}

  def handle_call(:step, _from, state) do
    offsets = Params.neighbor_offsets()
    cells = Wetware.Gel.Index.list_cells()

    charge_map =
      cells
      |> Enum.map(fn {coord, pid} -> {coord, Cell.get_charge(pid)} end)
      |> Map.new()

    new_count = state.step_count + 1

    tasks =
      Enum.map(cells, fn {{x, y} = coord, pid} ->
        neighbor_charges =
          for {dy, dx} <- offsets,
              into: %{} do
            ncoord = {x + dx, y + dy}
            {{dx, dy}, Map.get(charge_map, ncoord, 0.0)}
          end

        # Deposit pending input into empty neighbors for on-demand spawning.
        if charge_map[coord] > state.params.activation_threshold do
          Enum.each(offsets, fn {dy, dx} ->
            target = {x + dx, y + dy}

            if not Map.has_key?(charge_map, target) do
              Wetware.Gel.Index.add_pending(target, charge_map[coord] * 0.03)
            end
          end)
        end

        Task.async(fn -> Cell.step_with_charges(pid, neighbor_charges, new_count) end)
      end)

    Task.await_many(tasks, 30_000)

    {_, post_spawn_state} =
      Wetware.Gel.Index.take_pending_above(state.params.spawn_threshold)
      |> Enum.reduce({:ok, state}, fn {coord, amount}, {_ok, acc_state} ->
        {result, next_state} = ensure_cell_impl(coord, :propagation_spawn, [kind: :interstitial], acc_state)

        if match?({:ok, _}, result), do: Cell.stimulate(coord, amount)

        {result, next_state}
      end)

    Resonance.observe_step(new_count)
    Wetware.Gel.Lifecycle.tick(new_count)
    {:reply, {:ok, new_count}, %{post_spawn_state | step_count: new_count}}
  end

  def handle_call(:get_charges, _from, %{started: false} = state), do: {:reply, {:error, :not_booted}, state}

  def handle_call(:get_charges, _from, state) do
    charges =
      Wetware.Gel.Index.list_cells()
      |> Enum.map(fn {coord, pid} -> {coord, Cell.get_charge(pid)} end)
      |> Map.new()

    {:reply, charges, state}
  end

  def handle_call(:step_count, _from, state), do: {:reply, state.step_count, state}
  def handle_call({:set_step_count, n}, _from, state), do: {:reply, :ok, %{state | step_count: n}}
  def handle_call(:params, _from, state), do: {:reply, state.params, state}
  def handle_call(:reset_cells, _from, state) do
    Wetware.Gel.Index.list_cells()
    |> Enum.each(fn {coord, pid} ->
      Process.exit(pid, :normal)
      :ok = Wetware.Gel.Index.delete_cell(coord)
    end)

    :ok = Wetware.Gel.Index.clear_snapshots()
    :ok = Wetware.Gel.Index.clear_pending()

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:stimulate_region, cx, cy, radius, strength}, state) do
    r2 = radius * radius

    next_state =
      for y <- (cy - radius)..(cy + radius),
          x <- (cx - radius)..(cx + radius),
          (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2,
          reduce: state do
        acc_state ->
          {result, updated_state} = ensure_cell_impl({x, y}, :region_stimulus, [kind: :interstitial], acc_state)
          if match?({:ok, _}, result), do: Cell.stimulate({x, y}, strength)
          updated_state
      end

    {:noreply, next_state}
  end

  defp ensure_cell_impl({x, y} = coord, _reason, opts, state) do
    case Wetware.Gel.Index.cell_pid(coord) do
      {:ok, pid} ->
        maybe_apply_cell_attrs(pid, opts)
        {{:ok, pid}, state}

      :error ->
        snapshot =
          case Wetware.Gel.Index.take_snapshot(coord) do
            {:ok, snap} -> snap
            :error -> nil
          end

        kind = Keyword.get(opts, :kind, snapshot_kind(snapshot))
        owners = merged_owners(snapshot, opts)

        child_spec =
          {Cell,
           x: x,
           y: y,
           params: state.params,
           kind: kind,
           owners: owners,
           step_count: state.step_count}

        sup = {:via, PartitionSupervisor, {Wetware.CellSupervisors, coord}}

        case DynamicSupervisor.start_child(sup, child_spec) do
          {:ok, pid} ->
            :ok = Wetware.Gel.Index.put_cell(coord, pid)
            wire_neighbors(coord, pid)
            maybe_restore_snapshot(pid, snapshot)
            maybe_apply_cell_attrs(pid, opts)
            {{:ok, pid}, state}

          {:error, {:already_started, pid}} ->
            :ok = Wetware.Gel.Index.put_cell(coord, pid)
            wire_neighbors(coord, pid)
            maybe_restore_snapshot(pid, snapshot)
            maybe_apply_cell_attrs(pid, opts)
            {{:ok, pid}, state}

          {:error, reason} ->
            {{:error, reason}, state}
        end
    end
  end

  defp maybe_apply_cell_attrs(pid, opts) do
    if owner = Keyword.get(opts, :owner) do
      _ = Cell.add_owner(pid, owner)
    end

    :ok
  end

  defp maybe_restore_snapshot(_pid, nil), do: :ok

  defp maybe_restore_snapshot(pid, snapshot) do
    neighbors = Map.get(snapshot, :neighbors, %{})

    attrs = [
      kind: Map.get(snapshot, :kind, :interstitial),
      owners: Map.get(snapshot, :owners, []),
      last_step: Map.get(snapshot, :last_step, 0),
      last_active_step: Map.get(snapshot, :last_active_step, 0)
    ]

    Cell.restore(pid, Map.get(snapshot, :charge, 0.0), neighbors, attrs)
  end

  defp snapshot_cell(coord, pid) do
    try do
      state = Cell.get_state(pid)

      snapshot = %{
        charge: state.charge,
        kind: state.kind,
        owners: state.owners,
        neighbors: state.neighbors,
        last_step: state.last_step,
        last_active_step: state.last_active_step
      }

      :ok = Wetware.Gel.Index.put_snapshot(coord, snapshot)
    catch
      :exit, _ -> :ok
    end
  end

  defp snapshot_kind(nil), do: :interstitial
  defp snapshot_kind(snapshot), do: Map.get(snapshot, :kind, :interstitial)

  defp merged_owners(snapshot, opts) do
    snapshot_owners = if snapshot, do: Map.get(snapshot, :owners, []), else: []

    owner =
      case Keyword.get(opts, :owner) do
        nil -> []
        value -> [value]
      end

    explicit_owners = Keyword.get(opts, :owners, [])

    (snapshot_owners ++ owner ++ explicit_owners)
    |> Enum.uniq()
  end

  defp wire_neighbors({x, y}, pid) do
    Enum.each(Params.neighbor_offsets(), fn {dy, dx} ->
      ncoord = {x + dx, y + dy}

      case Wetware.Gel.Index.cell_pid(ncoord) do
        {:ok, npid} ->
          _ = Cell.connect_neighbor(pid, {dx, dy})
          _ = Cell.connect_neighbor(npid, {-dx, -dy})

        :error ->
          :ok
      end
    end)
  end
end
