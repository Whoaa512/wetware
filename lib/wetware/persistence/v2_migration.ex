defmodule Wetware.Persistence.V2Migration do
  @moduledoc "Transforms legacy elixir-v2 dense state into elixir-v3-sparse."

  alias Wetware.Params

  def to_sparse_state(v2_state) do
    offsets = Params.neighbor_offsets()
    p = Params.default()

    charges = v2_state["charges"] || []
    weights = v2_state["weights"] || []
    crystallized = v2_state["crystallized"] || []

    cells =
      for {row, y} <- Enum.with_index(charges),
          {charge, x} <- Enum.with_index(row),
          charge > 0.0,
          into: %{} do
        neighbor_map =
          offsets
          |> Enum.with_index()
          |> Enum.map(fn {{dy, dx}, i} ->
            w = get_in(weights, [Access.at(y), Access.at(x), Access.at(i)]) || p.w_init
            c = get_in(crystallized, [Access.at(y), Access.at(x), Access.at(i)]) || false
            {"#{dx}:#{dy}", %{"weight" => w, "crystallized" => c}}
          end)
          |> Map.new()

        {"#{x}:#{y}",
         %{
           "charge" => charge,
           "kind" => "interstitial",
           "owners" => [],
           "last_step" => v2_state["step_count"] || 0,
           "last_active_step" => v2_state["step_count"] || 0,
           "neighbors" => neighbor_map
         }}
      end

    %{
      "version" => "elixir-v3-sparse",
      "step_count" => v2_state["step_count"] || 0,
      "params" => Map.get(v2_state, "params", %{}),
      "cells" => cells,
      "concepts" => Map.get(v2_state, "concepts", %{}),
      "associations" => Map.get(v2_state, "associations", %{})
    }
  end
end
