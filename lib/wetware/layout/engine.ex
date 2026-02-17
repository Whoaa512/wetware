defmodule Wetware.Layout.Engine do
  @moduledoc "GenServer wrapper around a pluggable layout strategy."

  use GenServer

  @default_strategy Wetware.Layout.Proximity

  def start_link(opts \\ []) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    GenServer.start_link(__MODULE__, %{strategy: strategy}, name: __MODULE__)
  end

  def place(name, tags, existing) do
    GenServer.call(__MODULE__, {:place, name, tags, existing})
  end

  def strategy, do: GenServer.call(__MODULE__, :strategy)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:place, name, tags, existing}, _from, state) do
    pos = state.strategy.place(name, tags, existing)
    {:reply, pos, state}
  end

  def handle_call(:strategy, _from, state), do: {:reply, state.strategy, state}
end
