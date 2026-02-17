defmodule Wetware.Gel.Lifecycle do
  @moduledoc """
  Periodic sparse-cell lifecycle sweeps.

  Despawns dormant, low-charge, non-crystallized non-concept cells.
  """

  use GenServer

  alias Wetware.{Cell, Gel}

  @sweep_interval_ms 5_000

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def tick(step_count), do: GenServer.cast(__MODULE__, {:tick, step_count})

  @impl true
  def init(_) do
    schedule_sweep()
    {:ok, %{last_step: 0}}
  end

  @impl true
  def handle_cast({:tick, step_count}, state) do
    {:noreply, %{state | last_step: step_count}}
  end

  @impl true
  def handle_info(:sweep, state) do
    do_sweep(state.last_step)
    schedule_sweep()
    {:noreply, state}
  end

  defp do_sweep(current_step) do
    p = Gel.params() || Wetware.Params.default()

    Wetware.Gel.Index.list_cells()
    |> Enum.each(fn {{x, y}, pid} ->
      case Cell.get_state(pid) do
        %{kind: :concept} ->
          :ok

        %{kind: kind, owners: owners, last_active_step: last_active, charge: charge, neighbors: neighbors, last_step: last_step} ->
          dormant_steps = max(current_step - last_active, 0)
          crystallized? = Enum.any?(neighbors, fn {_k, v} -> Map.get(v, :crystallized, false) end)

          if dormant_steps >= p.despawn_dormancy_ttl and charge <= 0.01 and not crystallized? do
            snapshot = %{
              charge: charge,
              kind: kind,
              owners: owners,
              neighbors: neighbors,
              last_step: last_step,
              last_active_step: last_active
            }

            :ok = Wetware.Gel.Index.put_snapshot({x, y}, snapshot)
            Process.exit(pid, :normal)
            Wetware.Gel.Index.delete_cell({x, y})
          end

        _ ->
          :ok
      end
    end)
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
