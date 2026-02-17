defmodule Wetware.Params do
  @moduledoc """
  Physics parameters for the gel substrate.
  Same constants as the Python v1 — the underlying reality doesn't change,
  just the medium it runs on.
  """

  defstruct width: 80,
            height: 80,
            # original — balanced
            propagation_rate: 0.12,
            # moderate dissipation
            charge_decay: 0.06,
            activation_threshold: 0.1,
            # slow wiring — must be earned
            learning_rate: 0.015,
            # connections fade moderately
            decay_rate: 0.007,
            # meaningful but achievable
            crystal_threshold: 0.80,
            crystal_decay_factor: 0.05,
            w_init: 0.1,
            w_min: 0.01,
            w_max: 1.0

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          propagation_rate: float(),
          charge_decay: float(),
          activation_threshold: float(),
          learning_rate: float(),
          decay_rate: float(),
          crystal_threshold: float(),
          crystal_decay_factor: float(),
          w_init: float(),
          w_min: float(),
          w_max: float()
        }

  @doc "Default parameters matching Python v1."
  def default, do: %__MODULE__{}

  @doc "8-connected neighbor offsets: {dy, dx}"
  def neighbor_offsets do
    [{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1}]
  end

  @doc "Number of neighbor directions."
  def num_neighbors, do: 8
end
