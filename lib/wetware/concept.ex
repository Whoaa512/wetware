defmodule Wetware.Concept do
  @moduledoc """
  A named concept that owns a circular region of the gel.

  Concepts are the semantic layer on top of the substrate —
  named regions that accumulate meaning through use.
  Each concept knows its center, radius, tags, and can report
  its charge level and associations with other concepts.
  """

  use GenServer

  alias Wetware.{Cell, Params}

  defstruct [:name, :cx, :cy, :r, tags: []]

  @type t :: %__MODULE__{
          name: String.t(),
          cx: non_neg_integer(),
          cy: non_neg_integer(),
          r: non_neg_integer(),
          tags: [String.t()]
        }

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts) do
    concept = Keyword.fetch!(opts, :concept)
    GenServer.start_link(__MODULE__, concept, name: via(concept.name))
  end

  def via(name), do: {:via, Registry, {Wetware.ConceptRegistry, name}}

  @doc "Stimulate all cells in this concept's region."
  def stimulate(name, strength \\ 1.0) do
    GenServer.cast(via(name), {:stimulate, strength})
  end

  @doc "Get the mean charge across the concept's region."
  def charge(name) do
    GenServer.call(via(name), :charge, 15_000)
  end

  @doc "Find associated concepts via inter-region connection weights."
  def associations(name) do
    GenServer.call(via(name), :associations, 30_000)
  end

  @doc "Get concept info."
  def info(name) do
    GenServer.call(via(name), :info)
  end

  @doc "List all registered concepts."
  def list_all do
    Registry.select(Wetware.ConceptRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  @doc "Load concepts from a JSON file."
  def load_from_json(path) do
    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"concepts" => concepts}} ->
            Enum.map(concepts, fn {name, info} ->
              %__MODULE__{
                name: name,
                cx: info["cx"],
                cy: info["cy"],
                r: info["r"],
                tags: info["tags"] || []
              }
            end)

          {:ok, _} ->
            {:error, :invalid_format}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Register all concepts from a list."
  def register_all(concepts) when is_list(concepts) do
    Enum.each(concepts, fn concept ->
      {:ok, _} =
        DynamicSupervisor.start_child(
          Wetware.ConceptSupervisor,
          {__MODULE__, concept: concept}
        )
    end)

    :ok
  end

  # ── Server ──────────────────────────────────────────────────

  @impl true
  def init(concept) do
    {:ok, concept}
  end

  @impl true
  def handle_cast({:stimulate, strength}, concept) do
    cells_in_region(concept)
    |> Enum.each(fn {x, y} -> Cell.stimulate({x, y}, strength) end)

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
        |> Enum.map(fn {x, y} ->
          case Cell.get_state({x, y}) do
            %{charge: c} -> c
            _ -> 0.0
          end
        end)
        |> Enum.sum()

      {:reply, total / length(cells), concept}
    end
  end

  def handle_call(:associations, _from, concept) do
    my_cells = cells_in_region(concept) |> MapSet.new()

    # Get all other concepts
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

    # For each other concept, measure cross-region connection strength
    associations =
      Enum.map(other_concepts, fn other ->
        other_cells = cells_in_region(other) |> MapSet.new()

        # Check border cells — cells in my region whose neighbors are in other region
        border_weights =
          for {x, y} <- my_cells,
              {dy, dx} <- Params.neighbor_offsets(),
              nx = x + dx,
              ny = y + dy,
              MapSet.member?(other_cells, {nx, ny}) do
            case Cell.get_state({x, y}) do
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
    {:reply, concept, concept}
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp cells_in_region(%{cx: cx, cy: cy, r: r}) do
    p = Params.default()
    r2 = r * r

    for y <- max(0, cy - r)..min(p.height - 1, cy + r),
        x <- max(0, cx - r)..min(p.width - 1, cx + r),
        (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2 do
      {x, y}
    end
  end
end
