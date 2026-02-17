defmodule Wetware.Gel do
  @moduledoc """
  The gel substrate — an 80×80 grid of Cell processes.

  This module supervises the grid and provides the management layer:
  creating cells, wiring topology, triggering steps, and querying state.

  6400 processes. BEAM handles millions. This IS the wetware.
  """

  use GenServer

  alias Wetware.{Cell, Params}

  defstruct [
    params: %Params{},
    step_count: 0,
    started: false
  ]

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    params = Keyword.get(opts, :params, Params.default())
    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  @doc "Initialize the gel: spawn all cells and wire topology."
  def boot do
    GenServer.call(__MODULE__, :boot, 120_000)
  end

  @doc "Check if the gel is booted."
  def booted? do
    GenServer.call(__MODULE__, :booted?)
  end

  @doc "Run one physics step across all cells."
  def step do
    GenServer.call(__MODULE__, :step, 60_000)
  end

  @doc "Run n physics steps."
  def step(n) when is_integer(n) and n > 0 do
    Enum.each(1..n, fn _ -> step() end)
  end

  @doc "Stimulate a circular region of cells."
  def stimulate_region(cx, cy, radius, strength \\ 1.0) do
    GenServer.cast(__MODULE__, {:stimulate_region, cx, cy, radius, strength})
  end

  @doc "Get charge values for all cells as a 2D list."
  def get_charges do
    GenServer.call(__MODULE__, :get_charges, 60_000)
  end

  @doc "Get the full state of a specific cell."
  def get_cell(x, y) do
    Cell.get_state({x, y})
  end

  @doc "Get current step count."
  def step_count do
    GenServer.call(__MODULE__, :step_count)
  end

  @doc "Set step count (for restoring state)."
  def set_step_count(n) when is_integer(n) and n >= 0 do
    GenServer.call(__MODULE__, {:set_step_count, n})
  end

  @doc "Get the params."
  def params do
    GenServer.call(__MODULE__, :params)
  end

  # ── Server ──────────────────────────────────────────────────

  @impl true
  def init(params) do
    {:ok, %__MODULE__{params: params}}
  end

  @impl true
  def handle_call(:boot, _from, %{started: true} = state) do
    {:reply, {:ok, :already_booted}, state}
  end

  def handle_call(:boot, _from, state) do
    p = state.params
    IO.puts("🧬 Booting gel substrate: #{p.width}×#{p.height} = #{p.width * p.height} cells...")

    # 1. Start all cell processes
    for y <- 0..(p.height - 1), x <- 0..(p.width - 1) do
      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Wetware.CellSupervisor,
          {Cell, x: x, y: y, params: p}
        )
    end

    IO.puts("   ✓ #{p.width * p.height} cells spawned")

    # 2. Wire topology — each cell gets its 8 neighbors
    offsets = Params.neighbor_offsets()

    for y <- 0..(p.height - 1), x <- 0..(p.width - 1) do
      neighbors =
        for {dy, dx} <- offsets,
            ny = y + dy,
            nx = x + dx,
            ny >= 0 and ny < p.height,
            nx >= 0 and nx < p.width,
            into: %{} do
          [{pid, _}] = Registry.lookup(Wetware.CellRegistry, {nx, ny})
          {{dx, dy}, pid}
        end

      Cell.set_neighbors({x, y}, neighbors)
    end

    IO.puts("   ✓ Topology wired (8-connected)")
    IO.puts("🧬 Gel substrate online.")

    {:reply, :ok, %{state | started: true}}
  end

  def handle_call(:booted?, _from, state) do
    {:reply, state.started, state}
  end

  def handle_call(:step, _from, %{started: false} = state) do
    {:reply, {:error, :not_booted}, state}
  end

  def handle_call(:step, _from, state) do
    p = state.params
    offsets = Params.neighbor_offsets()

    # Phase 1: Collect ALL charges (read phase — no mutations)
    charge_grid =
      for y <- 0..(p.height - 1), into: %{} do
        row =
          for x <- 0..(p.width - 1), into: %{} do
            {x, Cell.get_charge({x, y})}
          end

        {y, row}
      end

    # Phase 2: Send each cell its neighbor charges and let it update
    tasks =
      for y <- 0..(p.height - 1), x <- 0..(p.width - 1) do
        neighbor_charges =
          for {dy, dx} <- offsets,
              ny = y + dy,
              nx = x + dx,
              ny >= 0 and ny < p.height,
              nx >= 0 and nx < p.width,
              into: %{} do
            {{dx, dy}, charge_grid[ny][nx]}
          end

        Task.async(fn -> Cell.step_with_charges({x, y}, neighbor_charges) end)
      end

    Task.await_many(tasks, 30_000)

    new_count = state.step_count + 1
    {:reply, {:ok, new_count}, %{state | step_count: new_count}}
  end

  def handle_call(:get_charges, _from, %{started: false} = state) do
    {:reply, {:error, :not_booted}, state}
  end

  def handle_call(:get_charges, _from, state) do
    p = state.params

    charges =
      for y <- 0..(p.height - 1) do
        for x <- 0..(p.width - 1) do
          Cell.get_charge({x, y})
        end
      end

    {:reply, charges, state}
  end

  def handle_call(:step_count, _from, state) do
    {:reply, state.step_count, state}
  end

  def handle_call({:set_step_count, n}, _from, state) do
    {:reply, :ok, %{state | step_count: n}}
  end

  def handle_call(:params, _from, state) do
    {:reply, state.params, state}
  end

  @impl true
  def handle_cast({:stimulate_region, cx, cy, radius, strength}, state) do
    p = state.params
    r2 = radius * radius

    for y <- 0..(p.height - 1),
        x <- 0..(p.width - 1),
        (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2 do
      Cell.stimulate({x, y}, strength)
    end

    {:noreply, state}
  end
end
