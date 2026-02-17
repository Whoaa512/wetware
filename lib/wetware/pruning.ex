defmodule Wetware.Pruning do
  @moduledoc "Concept pruning for dormant concepts that have not earned persistence."

  alias Wetware.{Cell, Concept, DataPaths, Resonance}

  @default_dormancy_steps 500

  @doc "List concepts dormant for N+ steps, excluding crystallized concepts."
  def candidates(opts \\ []) do
    min_steps = Keyword.get(opts, :dormancy_steps, @default_dormancy_steps)
    threshold = Keyword.get(opts, :threshold, 0.05)

    Concept.list_all()
    |> Enum.map(fn name ->
      dormancy = Resonance.dormancy(name, threshold: threshold)
      crystallized = crystallized_concept?(name)

      %{
        name: name,
        dormant_steps: dormancy.dormant_steps,
        last_active_step: dormancy.last_active_step,
        charge: dormancy.charge,
        crystallized: crystallized
      }
    end)
    |> Enum.filter(fn item -> item.dormant_steps >= min_steps and not item.crystallized end)
    |> Enum.sort_by(fn item -> {-item.dormant_steps, item.name} end)
  end

  @doc "Prune one concept and append history."
  def prune(concept_name, _opts \\ []) do
    if crystallized_concept?(concept_name) do
      {:error, :crystallized}
    else
      with :ok <- Resonance.remove_concept(concept_name, concepts_path: DataPaths.concepts_path()) do
        history = load_history()

        entry = %{
          "concept" => concept_name,
          "pruned_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "step_count" => Wetware.Gel.step_count()
        }

        updated = %{"entries" => [entry | Map.get(history, "entries", [])]}
        save_history(updated)
        :ok
      end
    end
  end

  @doc "Prune all dormant candidates. Use `dry_run: true` to only list candidates."
  def prune_all(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    list = candidates(opts)

    if dry_run do
      {:ok, list}
    else
      results = Enum.map(list, fn item -> {item.name, prune(item.name, opts)} end)
      {:ok, results}
    end
  end

  defp crystallized_concept?(name) do
    info = Concept.info(name)

    cells_in_region(info)
    |> Enum.any?(fn {x, y} ->
      state = Cell.get_state({x, y})

      state.neighbors
      |> Enum.any?(fn {_offset, data} -> Map.get(data, :crystallized, false) end)
    end)
  end

  defp cells_in_region(%{cx: cx, cy: cy, r: r}) do
    p = Wetware.Params.default()
    r2 = r * r

    for y <- max(0, cy - r)..min(p.height - 1, cy + r),
        x <- max(0, cx - r)..min(p.width - 1, cx + r),
        (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2 do
      {x, y}
    end
  end

  defp load_history do
    path = DataPaths.pruned_history_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, data} ->
          case Jason.decode(data) do
            {:ok, decoded} -> decoded
            _ -> %{"entries" => []}
          end

        _ ->
          %{"entries" => []}
      end
    else
      %{"entries" => []}
    end
  end

  defp save_history(state) do
    path = DataPaths.pruned_history_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(state, pretty: true))
    :ok
  end
end
