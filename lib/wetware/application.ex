defmodule Wetware.Application do
  @moduledoc "Application supervisor for Wetware sparse gel runtime."

  use Application

  @impl true
  def start(_type, _args) do
    cell_partitions = System.schedulers_online() * 4

    children = [
      {Registry, keys: :unique, name: Wetware.CellRegistry, partitions: cell_partitions},
      {Registry, keys: :unique, name: Wetware.ConceptRegistry},
      {PartitionSupervisor,
       child_spec: DynamicSupervisor, name: Wetware.CellSupervisors, partitions: cell_partitions},
      {DynamicSupervisor, name: Wetware.ConceptSupervisor, strategy: :one_for_one},
      Wetware.Gel.Index,
      Wetware.Layout.Engine,
      Wetware.Gel.Lifecycle,
      Wetware.Gel,
      Wetware.Associations,
      Wetware.Mood
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Wetware.Supervisor)
  end
end
