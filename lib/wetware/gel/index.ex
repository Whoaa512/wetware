defmodule Wetware.Gel.Index do
  @moduledoc """
  ETS owner for sparse gel indexes:
  - coord -> pid
  - coord -> dormant snapshot
  - pending input per coord
  - current sparse bounds
  """

  use GenServer

  @cells_table :wetware_cells
  @snapshots_table :wetware_cell_snapshots
  @pending_table :wetware_pending_input
  @bounds_table :wetware_bounds

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def put_cell(coord, pid), do: GenServer.call(__MODULE__, {:put_cell, coord, pid})
  def delete_cell(coord), do: GenServer.call(__MODULE__, {:delete_cell, coord})
  def put_snapshot(coord, snapshot), do: GenServer.call(__MODULE__, {:put_snapshot, coord, snapshot})
  def delete_snapshot(coord), do: GenServer.call(__MODULE__, {:delete_snapshot, coord})
  def take_snapshot(coord), do: GenServer.call(__MODULE__, {:take_snapshot, coord})
  def clear_snapshots, do: GenServer.call(__MODULE__, :clear_snapshots)
  def clear_pending, do: GenServer.call(__MODULE__, :clear_pending)

  def cell_pid(coord) do
    case :ets.lookup(@cells_table, coord) do
      [{^coord, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  def list_cells do
    :ets.tab2list(@cells_table)
    |> Enum.map(fn {coord, pid} -> {coord, pid} end)
  end

  def list_coords do
    :ets.tab2list(@cells_table)
    |> Enum.map(fn {coord, _pid} -> coord end)
  end

  def snapshot(coord) do
    case :ets.lookup(@snapshots_table, coord) do
      [{^coord, snapshot}] -> {:ok, snapshot}
      [] -> :error
    end
  end

  def list_snapshots do
    :ets.tab2list(@snapshots_table)
    |> Enum.map(fn {coord, snapshot} -> {coord, snapshot} end)
  end

  def bounds do
    case :ets.lookup(@bounds_table, :bounds) do
      [{:bounds, b}] -> b
      [] -> nil
    end
  end

  def recompute_bounds do
    GenServer.call(__MODULE__, :recompute_bounds)
  end

  def add_pending(coord, amount), do: GenServer.call(__MODULE__, {:add_pending, coord, amount})
  def take_pending_above(threshold), do: GenServer.call(__MODULE__, {:take_pending_above, threshold})

  @impl true
  def init(_) do
    :ets.new(@cells_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@snapshots_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@pending_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@bounds_table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:put_cell, {x, y} = coord, pid}, _from, state) do
    :ets.insert(@cells_table, {coord, pid})
    :ets.delete(@snapshots_table, coord)

    bounds =
      case bounds() do
        nil -> %{min_x: x, max_x: x, min_y: y, max_y: y}
        b -> %{min_x: min(b.min_x, x), max_x: max(b.max_x, x), min_y: min(b.min_y, y), max_y: max(b.max_y, y)}
      end

    :ets.insert(@bounds_table, {:bounds, bounds})
    {:reply, :ok, state}
  end

  def handle_call({:delete_cell, coord}, _from, state) do
    :ets.delete(@cells_table, coord)
    recompute_bounds_now()
    {:reply, :ok, state}
  end

  def handle_call({:put_snapshot, coord, snapshot}, _from, state) do
    :ets.insert(@snapshots_table, {coord, snapshot})
    {:reply, :ok, state}
  end

  def handle_call({:delete_snapshot, coord}, _from, state) do
    :ets.delete(@snapshots_table, coord)
    {:reply, :ok, state}
  end

  def handle_call({:take_snapshot, coord}, _from, state) do
    result =
      case :ets.lookup(@snapshots_table, coord) do
        [{^coord, snapshot}] ->
          :ets.delete(@snapshots_table, coord)
          {:ok, snapshot}

        [] ->
          :error
      end

    {:reply, result, state}
  end

  def handle_call(:recompute_bounds, _from, state) do
    recompute_bounds_now()
    {:reply, :ok, state}
  end

  def handle_call({:add_pending, coord, amount}, _from, state) do
    current =
      case :ets.lookup(@pending_table, coord) do
        [{^coord, v}] -> v
        [] -> 0.0
      end

    :ets.insert(@pending_table, {coord, current + amount})
    {:reply, :ok, state}
  end

  def handle_call({:take_pending_above, threshold}, _from, state) do
    picked =
      :ets.tab2list(@pending_table)
      |> Enum.filter(fn {_coord, amount} -> amount >= threshold end)

    Enum.each(picked, fn {coord, _} -> :ets.delete(@pending_table, coord) end)

    {:reply, picked, state}
  end

  def handle_call(:clear_snapshots, _from, state) do
    :ets.delete_all_objects(@snapshots_table)
    {:reply, :ok, state}
  end

  def handle_call(:clear_pending, _from, state) do
    :ets.delete_all_objects(@pending_table)
    {:reply, :ok, state}
  end

  defp recompute_bounds_now do
    case list_coords() do
      [] -> :ets.delete(@bounds_table, :bounds)
      [{x, y} | rest] ->
        bounds =
          Enum.reduce(rest, %{min_x: x, max_x: x, min_y: y, max_y: y}, fn {cx, cy}, acc ->
            %{min_x: min(acc.min_x, cx), max_x: max(acc.max_x, cx), min_y: min(acc.min_y, cy), max_y: max(acc.max_y, cy)}
          end)

        :ets.insert(@bounds_table, {:bounds, bounds})
    end
  end
end
