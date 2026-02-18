defmodule Wetware.Gel do
  @moduledoc """
  Sparse, on-demand gel substrate.
  """

  use GenServer

  alias Wetware.{Cell, Params, Resonance}
  @reshape_interval 4
  @reshape_max_offset 4
  @cluster_interval 8
  @cluster_min_weight 0.12

  defstruct params: %Params{}, step_count: 0, started: false, concepts: %{}

  def start_link(opts \\ []) do
    params =
      opts
      |> Keyword.get(:params, Params.default())
      |> Params.with_topology_from_env()

    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  def boot, do: GenServer.call(__MODULE__, :boot, 120_000)
  def booted?, do: GenServer.call(__MODULE__, :booted?)

  def step, do: GenServer.call(__MODULE__, :step, 60_000)

  def step(n) when is_integer(n) and n > 0 do
    Enum.each(1..n, fn _ -> step() end)
  end

  def ensure_cell(coord, reason \\ :manual, opts \\ []),
    do: GenServer.call(__MODULE__, {:ensure_cell, coord, reason, opts})

  def despawn_cell(coord), do: GenServer.call(__MODULE__, {:despawn_cell, coord})

  def register_concept(concept), do: GenServer.call(__MODULE__, {:register_concept, concept})
  def unregister_concept(name), do: GenServer.call(__MODULE__, {:unregister_concept, name})

  def concepts, do: GenServer.call(__MODULE__, :concepts)

  def concept_region(name), do: GenServer.call(__MODULE__, {:concept_region, name})

  def concept_cells(name), do: GenServer.call(__MODULE__, {:concept_cells, name})

  def set_concepts(concepts) when is_map(concepts),
    do: GenServer.call(__MODULE__, {:set_concepts, concepts})

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

  def set_step_count(n) when is_integer(n) and n >= 0,
    do: GenServer.call(__MODULE__, {:set_step_count, n})

  def params, do: GenServer.call(__MODULE__, :params)
  def reset_cells, do: GenServer.call(__MODULE__, :reset_cells)

  @impl true
  def init(params) do
    {:ok, %__MODULE__{params: params}}
  end

  @impl true
  def handle_call(:boot, _from, %{started: true} = state),
    do: {:reply, {:ok, :already_booted}, state}

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
    parent = Map.get(concept, :parent)

    {cx, cy} =
      cond do
        is_integer(Map.get(concept, :cx)) and is_integer(Map.get(concept, :cy)) ->
          {concept.cx, concept.cy}

        true ->
          Wetware.Layout.Engine.place(name, tags, state.concepts)
      end

    info = %{center: {cx, cy}, r: r, tags: tags, parent: parent}

    coords =
      for y <- (cy - r)..(cy + r),
          x <- (cx - r)..(cx + r),
          (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r,
          do: {x, y}

    {_, post_seed_state} =
      Enum.reduce(
        coords,
        {{:ok, :seeded}, %{state | concepts: Map.put(state.concepts, name, info)}},
        fn coord, {_, acc_state} ->
          {_result, next_state} =
            ensure_cell_impl(coord, :concept_seed, [kind: :concept, owner: name], acc_state)

          {{:ok, :seeded}, next_state}
        end
      )

    reply_concept = Map.merge(concept, %{cx: cx, cy: cy, r: r})
    {:reply, {:ok, reply_concept}, post_seed_state}
  end

  def handle_call({:unregister_concept, name}, _from, state) do
    {:reply, :ok, %{state | concepts: Map.delete(state.concepts, name)}}
  end

  def handle_call(:concepts, _from, state), do: {:reply, state.concepts, state}

  def handle_call({:set_concepts, concepts}, _from, state),
    do: {:reply, :ok, %{state | concepts: concepts}}

  def handle_call({:concept_region, name}, _from, state) do
    case Map.get(state.concepts, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{center: {cx, cy}, r: r, tags: tags, parent: parent} ->
        {:reply, %{name: name, cx: cx, cy: cy, r: r, tags: tags, parent: parent}, state}
    end
  end

  def handle_call({:concept_cells, name}, _from, state) do
    coords =
      case Map.get(state.concepts, name) do
        nil ->
          []

        %{center: {cx, cy}, r: r} ->
          for y <- (cy - r)..(cy + r),
              x <- (cx - r)..(cx + r),
              (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r,
              do: {x, y}
      end

    {:reply, coords, state}
  end

  def handle_call(:step, _from, %{started: false} = state),
    do: {:reply, {:error, :not_booted}, state}

  def handle_call(:step, _from, state) do
    base_offsets = Params.neighbor_offsets(state.params)
    cells = Wetware.Gel.Index.list_cells()

    {signal_map, cell_state_map} =
      cells
      |> Enum.map(fn {coord, pid} ->
        cell_state = Cell.get_state(pid)

        {coord,
         {%{
            charge: Map.get(cell_state, :charge, 0.0),
            valence: Map.get(cell_state, :valence, 0.0)
          }, cell_state}}
      end)
      |> Enum.reduce({%{}, %{}}, fn {coord, {signal, cell_state}}, {signals, states} ->
        {Map.put(signals, coord, signal), Map.put(states, coord, cell_state)}
      end)

    new_count = state.step_count + 1

    tasks =
      Enum.map(cells, fn {{x, y} = coord, pid} ->
        source_state = Map.get(cell_state_map, coord, %{neighbors: %{}})
        offsets = source_state.neighbors |> Map.keys()

        neighbor_charges =
          for {dx, dy} <- offsets,
              into: %{} do
            ncoord = {x + dx, y + dy}
            {{dx, dy}, get_in(signal_map, [ncoord, :charge]) || 0.0}
          end

        neighbor_valences =
          for {dx, dy} <- offsets,
              into: %{} do
            ncoord = {x + dx, y + dy}
            {{dx, dy}, get_in(signal_map, [ncoord, :valence]) || 0.0}
          end

        # Deposit pending input into empty neighbors for on-demand spawning.
        coord_charge = get_in(signal_map, [coord, :charge]) || 0.0

        if coord_charge > state.params.activation_threshold do
          Enum.each(base_offsets, fn {dy, dx} ->
            target = {x + dx, y + dy}

            if not Map.has_key?(signal_map, target) do
              Wetware.Gel.Index.add_pending(target, coord_charge * 0.03)
            end
          end)
        end

        Task.async(fn ->
          Cell.step_with_charges(pid, neighbor_charges, neighbor_valences, new_count)
        end)
      end)

    Task.await_many(tasks, 30_000)
    maybe_reshape_topology(cells, cell_state_map, new_count, state.params)

    {_, post_spawn_state} =
      Wetware.Gel.Index.take_pending_above(state.params.spawn_threshold)
      |> Enum.reduce({:ok, state}, fn {coord, amount}, {_ok, acc_state} ->
        {result, next_state} =
          ensure_cell_impl(coord, :propagation_spawn, [kind: :interstitial], acc_state)

        if match?({:ok, _}, result), do: Cell.stimulate(coord, amount)

        {result, next_state}
      end)

    post_cluster_state = maybe_cluster_concepts(post_spawn_state, new_count)
    Wetware.Associations.decay_step()
    Resonance.observe_step(new_count)
    Wetware.Gel.Lifecycle.tick(new_count)
    {:reply, {:ok, new_count}, %{post_cluster_state | step_count: new_count}}
  end

  def handle_call(:get_charges, _from, %{started: false} = state),
    do: {:reply, {:error, :not_booted}, state}

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
    cells = Wetware.Gel.Index.list_cells()

    pending =
      Enum.reduce(cells, %{}, fn {coord, pid}, acc ->
        ref = Process.monitor(pid)
        Process.exit(pid, :shutdown)
        Map.put(acc, ref, {coord, pid})
      end)

    pending = await_cell_shutdown(pending, 2_000)

    if map_size(pending) > 0 do
      Enum.each(pending, fn {ref, {_coord, pid}} ->
        Process.demonitor(ref, [:flush])

        if Process.alive?(pid) do
          Process.exit(pid, :kill)
        end
      end)

      _ = await_cell_shutdown(pending, 500)
    end

    Enum.each(cells, fn {coord, _pid} ->
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
          {result, updated_state} =
            ensure_cell_impl({x, y}, :region_stimulus, [kind: :interstitial], acc_state)

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
            wire_neighbors(coord, pid, state.params)
            maybe_restore_snapshot(pid, snapshot)
            maybe_apply_cell_attrs(pid, opts)
            {{:ok, pid}, state}

          {:error, {:already_started, pid}} ->
            :ok = Wetware.Gel.Index.put_cell(coord, pid)
            wire_neighbors(coord, pid, state.params)
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

  defp await_cell_shutdown(pending, timeout_ms) when map_size(pending) == 0 or timeout_ms <= 0,
    do: pending

  defp await_cell_shutdown(pending, timeout_ms) do
    started = System.monotonic_time(:millisecond)

    receive do
      {:DOWN, ref, :process, _pid, _reason} ->
        await_cell_shutdown(Map.delete(pending, ref), timeout_ms - elapsed_since(started))
    after
      timeout_ms ->
        pending
    end
  end

  defp elapsed_since(started_ms) do
    max(System.monotonic_time(:millisecond) - started_ms, 0)
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

  defp wire_neighbors({x, y}, pid, params) do
    Enum.each(Params.neighbor_offsets(params), fn {dy, dx} ->
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

  defp maybe_reshape_topology(_cells, _cell_state_map, step_count, _params)
       when rem(step_count, @reshape_interval) != 0,
       do: :ok

  defp maybe_reshape_topology(cells, cell_state_map, _step_count, params) do
    pid_map = Map.new(cells)

    active =
      cell_state_map
      |> Enum.filter(fn {_coord, cell_state} ->
        Map.get(cell_state, :charge, 0.0) > params.activation_threshold
      end)

    Enum.each(active, fn {{x, y} = source_coord, source_state} ->
      source_neighbors = source_state |> Map.get(:neighbors, %{}) |> Map.keys() |> MapSet.new()

      target =
        active
        |> Enum.reject(fn {coord, _} -> coord == source_coord end)
        |> Enum.reject(fn {{tx, ty}, _} ->
          dx = tx - x
          dy = ty - y

          MapSet.member?(source_neighbors, {dx, dy}) or
            max(abs(dx), abs(dy)) <= 1 or
            max(abs(dx), abs(dy)) > @reshape_max_offset
        end)
        |> Enum.max_by(
          fn {{tx, ty}, tstate} ->
            distance = max(abs(tx - x), abs(ty - y))
            charge = Map.get(tstate, :charge, 0.0)
            charge - distance * 0.05
          end,
          fn -> nil end
        )

      if target do
        {{tx, ty}, _target_state} = target
        offset = {tx - x, ty - y}

        with {:ok, source_pid} <- Map.fetch(pid_map, source_coord),
             {:ok, target_pid} <- Map.fetch(pid_map, {tx, ty}) do
          _ = Cell.connect_neighbor(source_pid, offset)
          _ = Cell.connect_neighbor(target_pid, {-elem(offset, 0), -elem(offset, 1)})
        end
      end
    end)
  end

  defp maybe_cluster_concepts(state, step_count) when rem(step_count, @cluster_interval) != 0,
    do: state

  defp maybe_cluster_concepts(state, _step_count) do
    concept_names = state.concepts |> Map.keys() |> Enum.sort()

    Enum.reduce(concept_names, state, fn name, acc_state ->
      case Map.get(acc_state.concepts, name) do
        %{center: {cx, cy}, r: r} = info ->
          targets =
            Wetware.Associations.get(name, 4)
            |> Enum.filter(fn {other, weight} ->
              weight >= @cluster_min_weight and Map.has_key?(acc_state.concepts, other)
            end)

          case cluster_target_center({cx, cy}, targets, acc_state.concepts) do
            nil ->
              acc_state

            {tx, ty} ->
              new_center = {cx + step_delta(tx - cx), cy + step_delta(ty - cy)}

              if new_center == {cx, cy} or
                   not concept_center_available?(name, new_center, r, acc_state.concepts) do
                acc_state
              else
                moved_info = Map.put(info, :center, new_center)
                moved_concepts = Map.put(acc_state.concepts, name, moved_info)
                moved_state = %{acc_state | concepts: moved_concepts}
                seed_concept_cells(name, moved_info, moved_state)
              end
          end

        _ ->
          acc_state
      end
    end)
  end

  defp cluster_target_center(_source_center, [], _concepts), do: nil

  defp cluster_target_center({cx, cy}, targets, concepts) do
    {sum_x, sum_y, total_weight} =
      Enum.reduce(targets, {cx * 1.0, cy * 1.0, 1.0}, fn {other, weight}, {sx, sy, sw} ->
        %{center: {ox, oy}} = Map.fetch!(concepts, other)
        {sx + ox * weight, sy + oy * weight, sw + weight}
      end)

    {round(sum_x / total_weight), round(sum_y / total_weight)}
  end

  defp concept_center_available?(name, {x, y}, r, concepts) do
    Enum.all?(concepts, fn
      {^name, _info} ->
        true

      {_other, %{center: {ox, oy}, r: other_r}} ->
        min_dist = r + other_r + 1
        :math.sqrt((x - ox) * (x - ox) + (y - oy) * (y - oy)) >= min_dist
    end)
  end

  defp seed_concept_cells(name, %{center: {cx, cy}, r: r}, state) do
    concept_cells_for({cx, cy}, r)
    |> Enum.reduce(state, fn coord, acc_state ->
      {_result, next_state} =
        ensure_cell_impl(coord, :concept_cluster_move, [kind: :concept, owner: name], acc_state)

      next_state
    end)
  end

  defp concept_cells_for({cx, cy}, r) do
    for y <- (cy - r)..(cy + r),
        x <- (cx - r)..(cx + r),
        (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r,
        do: {x, y}
  end

  defp step_delta(v) when v > 0, do: 1
  defp step_delta(v) when v < 0, do: -1
  defp step_delta(_), do: 0
end
