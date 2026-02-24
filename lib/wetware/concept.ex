defmodule Wetware.Concept do
  alias Wetware.Util
  @moduledoc """
  Named concept process layered over sparse gel cells.
  """

  use GenServer

  alias Wetware.{Cell, Gel, Params, Util}

  defstruct [:name, :cx, :cy, :r, :parent, tags: []]

  @type t :: %__MODULE__{}

  def start_link(opts) do
    concept = Keyword.fetch!(opts, :concept)
    GenServer.start_link(__MODULE__, concept, name: via(concept.name))
  end

  def via(name), do: {:via, Registry, {Wetware.ConceptRegistry, name}}

  def stimulate(name, strength \\ 1.0, opts \\ []) do
    valence = Keyword.get(opts, :valence, 0.0)
    GenServer.cast(via(name), {:stimulate, strength, valence})
  end

  def charge(name), do: GenServer.call(via(name), :charge, 15_000)
  def valence(name), do: GenServer.call(via(name), :valence, 15_000)

  @doc "Update the concept's center position (called by Gel when clustering moves it)."
  def update_center(name, cx, cy) when is_integer(cx) and is_integer(cy) do
    GenServer.cast(via(name), {:update_center, cx, cy})
  end

  @doc "Update the concept's radius (called by Gel when region adapts)."
  def update_radius(name, r) when is_integer(r) and r > 0 do
    GenServer.cast(via(name), {:update_radius, r})
  end
  def associations(name), do: GenServer.call(via(name), :associations, 30_000)
  def info(name), do: GenServer.call(via(name), :info)

  @doc "Get the GenServer's own position without merging Gel data. For drift detection."
  def raw_position(name), do: GenServer.call(via(name), :raw_position)

  def children(name), do: children_of(name)
  def ancestry(name), do: ancestry_of(name)

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
          parent: info["parent"],
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
  def handle_cast({:update_center, cx, cy}, concept) do
    {:noreply, %{concept | cx: cx, cy: cy}}
  end

  def handle_cast({:update_radius, r}, concept) do
    {:noreply, %{concept | r: r}}
  end

  def handle_cast({:stimulate, strength, valence}, concept) do
    cells_in_region(concept)
    |> Enum.each(fn coord ->
      if match?([_ | _], Registry.lookup(Wetware.CellRegistry, coord)) do
        Cell.stimulate_emotional(coord, strength, valence)
      else
        # Cell not live — add pending input so it gets promoted on next gel step
        Wetware.Gel.Index.add_pending(coord, strength)
      end
    end)

    {:noreply, concept}
  end

  def handle_call(:raw_position, _from, concept) do
    {:reply, %{cx: concept.cx, cy: concept.cy, r: concept.r}, concept}
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

  def handle_call(:valence, _from, concept) do
    cells = cells_in_region(concept)

    if cells == [] do
      {:reply, 0.0, concept}
    else
      total =
        cells
        |> Enum.map(fn coord ->
          case safe_cell_state(coord) do
            %{valence: v} ->
              v

            _ ->
              case Wetware.Gel.Index.snapshot(coord) do
                {:ok, %{valence: v}} -> v
                _ -> 0.0
              end
          end
        end)
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
    _ = Util.safe_exit(fn -> Gel.unregister_concept(concept.name) end, :ok)
    :ok
  end

  defp cells_in_region(%{cx: cx, cy: cy, r: r}) do
    for y <- (cy - r)..(cy + r),
        x <- (cx - r)..(cx + r),
        (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r do
      {x, y}
    end
  end

  defp cell_charge(coord) do
    case safe_cell_state(coord) do
      %{charge: c} ->
        c

      _ ->
        # Fall back to snapshot data for cells not yet promoted to live
        case Wetware.Gel.Index.snapshot(coord) do
          {:ok, %{charge: c}} -> c
          _ -> 0.0
        end
    end
  end

  defp safe_cell_state({x, y}) do
    Util.safe_exit(fn -> Cell.get_state({x, y}) end, nil)
  end

  defp children_of(name) do
    list_all()
    |> Enum.map(&safe_info/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn concept -> concept.parent == name end)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp ancestry_of(name), do: ancestry_of(name, MapSet.new())

  defp ancestry_of(name, seen) do
    if MapSet.member?(seen, name) do
      []
    else
      case safe_info(name) do
        %__MODULE__{parent: parent} when is_binary(parent) and parent != "" ->
          [parent | ancestry_of(parent, MapSet.put(seen, name))]

        _ ->
          []
      end
    end
  end

  defp safe_info(name) do
    Util.safe_exit(fn -> info(name) end, nil)
  end
end
