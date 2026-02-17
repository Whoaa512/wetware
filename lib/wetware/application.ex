defmodule Wetware.Application do
  @moduledoc """
  Application supervisor for the Wetware.

  Starts the registries, supervisors, and gel manager.
  The gel itself boots on demand via Resonance.boot/0.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Cell registry — maps {x, y} tuples to cell PIDs
      {Registry, keys: :unique, name: Wetware.CellRegistry},

      # Concept registry — maps concept names to PIDs
      {Registry, keys: :unique, name: Wetware.ConceptRegistry},

      # Dynamic supervisor for cell processes
      {DynamicSupervisor, name: Wetware.CellSupervisor, strategy: :one_for_one},

      # Dynamic supervisor for concept processes
      {DynamicSupervisor, name: Wetware.ConceptSupervisor, strategy: :one_for_one},

      # Gel manager
      Wetware.Gel,

      # Co-activation association tracker
      Wetware.Associations
    ]

    opts = [strategy: :one_for_one, name: Wetware.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
