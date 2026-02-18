defmodule Wetware.Persistence do
  @moduledoc "Save/load sparse gel state to JSON (elixir-v3-sparse)."

  alias Wetware.{Cell, DataPaths, Gel, Params}

  @default_path DataPaths.gel_state_path()

  def save(path \\ @default_path) do
    p = Gel.params()
    step_count = Gel.step_count()
    live_cells = Wetware.Gel.Index.list_cells()
    snapshots = Wetware.Gel.Index.list_snapshots()

    live_map =
      live_cells
      |> Enum.map(fn {{x, y}, pid} ->
        {"#{x}:#{y}", serialize_cell_state(Cell.get_state(pid))}
      end)
      |> Map.new()

    snapshot_map =
      snapshots
      |> Enum.map(fn {{x, y}, snapshot} -> {"#{x}:#{y}", serialize_cell_state(snapshot)} end)
      |> Map.new()

    cell_map = Map.merge(snapshot_map, live_map)

    concepts =
      Gel.concepts()
      |> Enum.map(fn {name, info} ->
        {cx, cy} = info.center

        {name,
         %{
           "center" => [cx, cy],
           "r" => info.r,
           "tags" => info.tags,
           "charge" => Float.round(safe_concept_charge(name), 6)
         }}
      end)
      |> Map.new()

    state = %{
      "version" => "elixir-v3-sparse",
      "step_count" => step_count,
      "params" => %{
        "propagation_rate" => p.propagation_rate,
        "charge_decay" => p.charge_decay,
        "valence_propagation_rate" => p.valence_propagation_rate,
        "valence_decay" => p.valence_decay,
        "activation_threshold" => p.activation_threshold,
        "learning_rate" => p.learning_rate,
        "decay_rate" => p.decay_rate,
        "crystal_threshold" => p.crystal_threshold,
        "crystal_decay_factor" => p.crystal_decay_factor,
        "w_init" => p.w_init,
        "w_min" => p.w_min,
        "w_max" => p.w_max,
        "spawn_threshold" => p.spawn_threshold,
        "despawn_dormancy_ttl" => p.despawn_dormancy_ttl
      },
      "cells" => cell_map,
      "concepts" => concepts,
      "associations" => Wetware.Associations.export(),
      "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    json = Jason.encode!(state, pretty: true)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, json)
    :ok
  end

  def load(path \\ @default_path) do
    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, state} -> restore_state(state)
          {:error, reason} -> {:error, {:json_parse, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read, reason}}
    end
  end

  defp restore_state(%{"version" => "elixir-v3-sparse"} = state) do
    restore_sparse_state(state)
  end

  defp restore_state(%{"version" => "elixir-v2"} = state) do
    sparse = Wetware.Persistence.V2Migration.to_sparse_state(state)
    restore_sparse_state(sparse)
  end

  defp restore_state(state) do
    if Map.has_key?(state, "charges") do
      sparse = Wetware.Persistence.V2Migration.to_sparse_state(state)
      restore_sparse_state(sparse)
    else
      {:error, :unsupported_version}
    end
  end

  defp restore_sparse_state(state) do
    p = Gel.params() || Params.default()
    step_count = state["step_count"] || 0
    concepts = parse_concepts(state["concepts"] || %{})
    Gel.reset_cells()
    Gel.set_step_count(step_count)
    Gel.set_concepts(concepts)

    cells = state["cells"] || %{}

    Enum.each(cells, fn {key, data} ->
      {x, y} = parse_coord_key(key)

      {:ok, _pid} =
        Gel.ensure_cell({x, y}, :restore,
          kind: parse_kind(data["kind"]),
          owners: data["owners"] || []
        )

      weights_map =
        (data["neighbors"] || %{})
        |> Enum.map(fn {offset_key, info} ->
          {parse_offset_key(offset_key),
           %{weight: info["weight"] || p.w_init, crystallized: info["crystallized"] || false}}
        end)
        |> Map.new()

      Cell.restore({x, y}, data["charge"] || 0.0, weights_map,
        kind: parse_kind(data["kind"]),
        owners: data["owners"] || [],
        valence: data["valence"] || 0.0,
        last_step: data["last_step"] || step_count,
        last_active_step: data["last_active_step"] || step_count
      )
    end)

    case state["associations"] do
      nil -> :ok
      assoc_data -> Wetware.Associations.import(assoc_data)
    end

    :ok
  end

  defp serialize_cell_state(state) do
    neighbors =
      Map.get(state, :neighbors, %{})
      |> Enum.map(fn {{dx, dy}, entry} ->
        {"#{dx}:#{dy}",
         %{
           "weight" => Float.round(Map.get(entry, :weight, 0.0), 6),
           "crystallized" => Map.get(entry, :crystallized, false)
         }}
      end)
      |> Map.new()

    %{
      "charge" => Float.round(Map.get(state, :charge, 0.0), 6),
      "valence" => Float.round(Map.get(state, :valence, 0.0), 6),
      "kind" => Atom.to_string(Map.get(state, :kind, :interstitial)),
      "owners" => Map.get(state, :owners, []),
      "last_step" => Map.get(state, :last_step, 0),
      "last_active_step" => Map.get(state, :last_active_step, 0),
      "neighbors" => neighbors
    }
  end

  defp parse_concepts(concepts) do
    concepts
    |> Enum.map(fn {name, info} ->
      info = if is_map(info), do: info, else: %{}
      {cx, cy} = parse_center(info)
      r = info["r"] || info["base_radius"] || info["current_radius"] || 3
      tags = info["tags"] || []
      {name, %{center: {cx, cy}, r: r, tags: tags}}
    end)
    |> Map.new()
  end

  defp parse_center(%{"center" => [cx, cy]}), do: {cx, cy}
  defp parse_center(%{"cx" => cx, "cy" => cy}), do: {cx, cy}
  defp parse_center(_), do: {0, 0}

  defp parse_coord_key(key) do
    [x, y] = String.split(key, ":", parts: 2)
    {String.to_integer(x), String.to_integer(y)}
  end

  defp parse_offset_key(key) do
    [dx, dy] = String.split(key, ":", parts: 2)
    {String.to_integer(dx), String.to_integer(dy)}
  end

  defp parse_kind(nil), do: :interstitial
  defp parse_kind("concept"), do: :concept
  defp parse_kind("axon"), do: :axon
  defp parse_kind("interstitial"), do: :interstitial
  defp parse_kind(atom) when is_atom(atom), do: atom
  defp parse_kind(_), do: :interstitial

  defp safe_concept_charge(name) do
    try do
      Wetware.Concept.charge(name)
    catch
      :exit, _ -> 0.0
    end
  end
end
