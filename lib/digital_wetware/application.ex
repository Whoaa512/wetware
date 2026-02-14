defmodule DigitalWetware.Application do
  @moduledoc """
  Application supervisor for the Digital Wetware.

  Starts the registries, supervisors, and gel manager.
  The gel itself boots on demand via Resonance.boot/0.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Cell registry — maps {x, y} tuples to cell PIDs
      {Registry, keys: :unique, name: DigitalWetware.CellRegistry},

      # Concept registry — maps concept names to PIDs
      {Registry, keys: :unique, name: DigitalWetware.ConceptRegistry},

      # Dynamic supervisor for cell processes
      {DynamicSupervisor, name: DigitalWetware.CellSupervisor, strategy: :one_for_one},

      # Dynamic supervisor for concept processes
      {DynamicSupervisor, name: DigitalWetware.ConceptSupervisor, strategy: :one_for_one},

      # Gel manager
      DigitalWetware.Gel
    ]

    opts = [strategy: :one_for_one, name: DigitalWetware.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
