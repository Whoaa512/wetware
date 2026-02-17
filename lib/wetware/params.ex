defmodule Wetware.Params do
  @moduledoc """
  Physics and lifecycle parameters for the sparse gel substrate.
  """

  defstruct propagation_rate: 0.12,
            charge_decay: 0.06,
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

  @doc "8-connected neighbor offsets: {dy, dx}"
  def neighbor_offsets do
    [{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1}]
  end

  def num_neighbors, do: 8
end
