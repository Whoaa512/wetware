defmodule Wetware.Concept do
  @moduledoc """
  Named concept process layered over sparse gel cells.
  """

  use GenServer

  alias Wetware.{Cell, Gel, Params}

  defstruct [:name, :cx, :cy, :r, tags: []]

  @type t :: %__MODULE__{}

  def start_link(opts) do
    concept = Keyword.fetch!(opts, :concept)
    GenServer.start_link(__MODULE__, concept, name: via(concept.name))
  end

  def via(name), do: {:via, Registry, {Wetware.ConceptRegistry, name}}

  def stimulate(name, strength \\ 1.0), do: GenServer.cast(via(name), {:stimulate, strength})
  def charge(name), do: GenServer.call(via(name), :charge, 15_000)
  def associations(name), do: GenServer.call(via(name), :associations, 30_000)
  def info(name), do: GenServer.call(via(name), :info)

  def list_all do
    Registry.select(Wetware.ConceptRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  @doc "Load concepts from JSON. Supports v2 (cx/cy/r) and sparse tags-only input."
  def load_from_json(path) do
    with {:ok, data} <- File.read(path),
         {:ok, %{"concepts" => concepts}} <- Jason.decode(data) do
      concepts
      |> Enum.map(fn {name, info} ->
        %__MODULE__{
          name: name,
          cx: info["cx"],
          cy: info["cy"],
          r: info["r"] || 3,
          tags: info["tags"] || []
        }
      end)
    else
      {:ok, _} -> {:error, :invalid_format}
      {:error, reason} -> {:error, reason}
    end
  end

  def register_all(concepts) when is_list(concepts) do
    Enum.each(concepts, fn concept ->
      {:ok, _} =
        DynamicSupervisor.start_child(Wetware.ConceptSupervisor, {__MODULE__, concept: concept})
    end)

    :ok
  end

  @impl true
  def init(concept) do
    {:ok, registered} = Gel.register_concept(concept)
    {:ok, struct(__MODULE__, Map.from_struct(registered))}
  end

  @impl true
  def handle_cast({:stimulate, strength}, concept) do
    cells_in_region(concept)
    |> Enum.each(fn {x, y} ->
      if match?([_ | _], Registry.lookup(Wetware.CellRegistry, {x, y})),
        do: Cell.stimulate({x, y}, strength)
    end)

    {:noreply, concept}
  end

  @impl true
  def handle_call(:charge, _from, concept) do
    cells = cells_in_region(concept)

    if cells == [] do
      {:reply, 0.0, concept}
    else
      total =
        cells
        |> Enum.map(&cell_charge/1)
        |> Enum.sum()

      {:reply, total / length(cells), concept}
    end
  end

  def handle_call(:associations, _from, concept) do
    my_cells = cells_in_region(concept) |> MapSet.new()

    other_concepts =
      list_all()
      |> Enum.reject(&(&1 == concept.name))
      |> Enum.map(fn name ->
        case GenServer.call(via(name), :info) do
          %{} = c -> c
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    associations =
      Enum.map(other_concepts, fn other ->
        other_cells = cells_in_region(other) |> MapSet.new()

        border_weights =
          for {x, y} <- my_cells,
              {dy, dx} <- Params.neighbor_offsets(),
              nx = x + dx,
              ny = y + dy,
              MapSet.member?(other_cells, {nx, ny}) do
            case safe_cell_state({x, y}) do
              %{neighbors: neighbors} ->
                case Map.get(neighbors, {dx, dy}) do
                  %{weight: w} -> w
                  _ -> 0.0
                end

              _ ->
                0.0
            end
          end

        if border_weights == [] do
          nil
        else
          avg = Enum.sum(border_weights) / length(border_weights)
          {other.name, Float.round(avg, 4)}
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn {_name, w} -> -w end)

    {:reply, associations, concept}
  end

  def handle_call(:info, _from, concept) do
    info =
      case Gel.concept_region(concept.name) do
        %{cx: _cx} = region -> Map.merge(Map.from_struct(concept), region)
        _ -> Map.from_struct(concept)
      end

    {:reply, struct(__MODULE__, info), concept}
  end

  @impl true
  def terminate(_reason, concept) do
    try do
      _ = Gel.unregister_concept(concept.name)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  defp cells_in_region(%{cx: cx, cy: cy, r: r}) do
    for y <- (cy - r)..(cy + r),
        x <- (cx - r)..(cx + r),
        (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r do
      {x, y}
    end
  end

  defp cell_charge({x, y}) do
    case safe_cell_state({x, y}) do
      %{charge: c} -> c
      _ -> 0.0
    end
  end

  defp safe_cell_state({x, y}) do
    try do
      Cell.get_state({x, y})
    catch
      :exit, _ -> nil
    end
  end
end
