defmodule Wetware.Params do
  @moduledoc """
  Physics and lifecycle parameters for the sparse gel substrate.
  """

  defstruct propagation_rate: 0.12,
            charge_decay: 0.06,
            valence_propagation_rate: 0.08,
            valence_decay: 0.04,
            topology_mode: :grid2d,
            activation_threshold: 0.1,
            learning_rate: 0.015,
            decay_rate: 0.007,
            crystal_threshold: 0.80,
            crystal_decay_factor: 0.05,
            w_init: 0.1,
            w_min: 0.01,
            w_max: 1.0,
            spawn_threshold: 0.12,
            despawn_dormancy_ttl: 500

  @type t :: %__MODULE__{
          propagation_rate: float(),
          charge_decay: float(),
          valence_propagation_rate: float(),
          valence_decay: float(),
          topology_mode: :grid2d | :gel3d,
          activation_threshold: float(),
          learning_rate: float(),
          decay_rate: float(),
          crystal_threshold: float(),
          crystal_decay_factor: float(),
          w_init: float(),
          w_min: float(),
          w_max: float(),
          spawn_threshold: float(),
          despawn_dormancy_ttl: pos_integer()
        }

  def default, do: %__MODULE__{}

  def with_topology_from_env(%__MODULE__{} = params) do
    mode =
      case System.get_env("WETWARE_TOPOLOGY") do
        "3d" -> :gel3d
        "gel3d" -> :gel3d
        "grid2d" -> :grid2d
        _ -> params.topology_mode
      end

    %{params | topology_mode: mode}
  end

  @doc "8-connected neighbor offsets: {dy, dx}"
  def neighbor_offsets do
    neighbor_offsets(default())
  end

  def neighbor_offsets(%__MODULE__{topology_mode: :gel3d}) do
    for dy <- -2..2,
        dx <- -2..2,
        not (dy == 0 and dx == 0),
        do: {dy, dx}
  end

  def neighbor_offsets(%__MODULE__{}) do
    [{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1}]
  end

  def num_neighbors(params \\ default()), do: params |> neighbor_offsets() |> length()
end
