defmodule Wetware.Persistence do
  @moduledoc """
  Save and load gel state to JSON.

  The format is designed to be readable and compatible with Python v1
  in spirit — storing charges, weights, and crystallization state
  for the full grid.
  """

  alias Wetware.{Cell, Gel, Params}

  @default_path Path.expand("~/nova/projects/digital-wetware/gel_state_ex.json")

  @doc "Save the current gel state to a JSON file."
  def save(path \\ @default_path) do
    p = Gel.params()
    step_count = Gel.step_count()

    IO.puts("💾 Saving gel state (#{p.width}×#{p.height}, step #{step_count})...")

    # Collect all cell states
    cells =
      for y <- 0..(p.height - 1),
          x <- 0..(p.width - 1) do
        Cell.get_state({x, y})
      end

    # Build charge grid
    charges =
      for y <- 0..(p.height - 1) do
        for x <- 0..(p.width - 1) do
          cell = Enum.find(cells, fn c -> c.x == x and c.y == y end)
          Float.round(cell.charge, 6)
        end
      end

    # Build weights grid: for each cell, 8 neighbor weights
    # Using offset ordering from Params.neighbor_offsets()
    offsets = Params.neighbor_offsets()

    weights =
      for y <- 0..(p.height - 1) do
        for x <- 0..(p.width - 1) do
          cell = Enum.find(cells, fn c -> c.x == x and c.y == y end)

          Enum.map(offsets, fn offset ->
            case Map.get(cell.neighbors, offset) do
              %{weight: w} -> Float.round(w, 6)
              _ -> p.w_init
            end
          end)
        end
      end

    # Build crystallized grid
    crystallized =
      for y <- 0..(p.height - 1) do
        for x <- 0..(p.width - 1) do
          cell = Enum.find(cells, fn c -> c.x == x and c.y == y end)

          Enum.map(offsets, fn offset ->
            case Map.get(cell.neighbors, offset) do
              %{crystallized: c} -> c
              _ -> false
            end
          end)
        end
      end

    # Build concepts state
    concepts =
      Wetware.Concept.list_all()
      |> Enum.map(fn name ->
        info = Wetware.Concept.info(name)
        charge = Wetware.Concept.charge(name)

        {name,
         %{
           cx: info.cx,
           cy: info.cy,
           r: info.r,
           tags: info.tags,
           charge: Float.round(charge, 6)
         }}
      end)
      |> Map.new()

    # Export co-activation associations
    assoc_data = Wetware.Associations.export()

    state = %{
      version: "elixir-v2",
      step_count: step_count,
      params: %{
        width: p.width,
        height: p.height,
        propagation_rate: p.propagation_rate,
        charge_decay: p.charge_decay,
        activation_threshold: p.activation_threshold,
        learning_rate: p.learning_rate,
        decay_rate: p.decay_rate,
        crystal_threshold: p.crystal_threshold,
        crystal_decay_factor: p.crystal_decay_factor,
        w_init: p.w_init,
        w_min: p.w_min,
        w_max: p.w_max
      },
      charges: charges,
      weights: weights,
      crystallized: crystallized,
      concepts: concepts,
      associations: assoc_data,
      saved_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    json = Jason.encode!(state, pretty: true)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, json)

    IO.puts("   ✓ Saved to #{path} (#{byte_size(json)} bytes)")
    :ok
  end

  @doc "Load gel state from a JSON file."
  def load(path \\ @default_path) do
    IO.puts("📂 Loading gel state from #{path}...")

    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, state} ->
            restore_state(state)

          {:error, reason} ->
            {:error, {:json_parse, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read, reason}}
    end
  end

  defp restore_state(state) do
    charges = state["charges"]
    weights = state["weights"]
    crystallized = state["crystallized"]
    offsets = Params.neighbor_offsets()
    p = Gel.params()

    if charges == nil do
      {:error, :no_charges}
    else
      count =
        for y <- 0..(p.height - 1),
            x <- 0..(p.width - 1) do
          charge = get_in(charges, [Access.at(y), Access.at(x)]) || 0.0

          cell_weights = get_in(weights, [Access.at(y), Access.at(x)]) || []
          cell_cryst = get_in(crystallized, [Access.at(y), Access.at(x)]) || []

          weights_map =
            offsets
            |> Enum.with_index()
            |> Enum.map(fn {offset, i} ->
              w = Enum.at(cell_weights, i, p.w_init)
              c = Enum.at(cell_cryst, i, false)
              {offset, %{weight: w, crystallized: c}}
            end)
            |> Map.new()

          Cell.restore({x, y}, charge, weights_map)
        end

      restored = length(count)
      step_count = state["step_count"] || 0
      Gel.set_step_count(step_count)

      # Restore co-activation associations
      case state["associations"] do
        nil -> :ok
        assoc_data -> Wetware.Associations.import(assoc_data)
      end

      IO.puts("   ✓ Restored #{restored} cells from #{state["version"] || "unknown"} (step #{step_count})")
      :ok
    end
  end
end
