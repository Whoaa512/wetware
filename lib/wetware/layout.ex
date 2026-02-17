defmodule Wetware.Layout do
  @moduledoc """
  Compatibility wrapper around the v3 layout engine/strategy modules.

  New callers should use `Wetware.Layout.Engine` and `Wetware.Layout.Strategy`.
  """

  @default_r 3

  def find_position(anchor_concept, concepts) do
    existing =
      concepts
      |> Enum.map(fn c ->
        {Map.fetch!(c, :name),
         %{
           center: {Map.fetch!(c, :cx), Map.fetch!(c, :cy)},
           r: Map.get(c, :r, @default_r),
           tags: Map.get(c, :tags, [])
         }}
      end)
      |> Map.new()

    name = Map.get(anchor_concept, :name, "candidate")
    tags = Map.get(anchor_concept, :tags, [])
    Wetware.Layout.Engine.place(name, tags, existing)
  end

  def find_position_default(concepts, opts \\ []) do
    tags = Keyword.get(opts, :tags, [])

    existing =
      concepts
      |> Enum.with_index()
      |> Enum.map(fn {c, idx} ->
        {"c#{idx}",
         %{
           center: {Map.fetch!(c, :cx), Map.fetch!(c, :cy)},
           r: Map.get(c, :r, @default_r),
           tags: Map.get(c, :tags, [])
         }}
      end)
      |> Map.new()

    Wetware.Layout.Proximity.place("candidate", tags, existing)
  end

  def is_empty_spot({x, y}, concepts, opts \\ []) do
    r = Keyword.get(opts, :r, @default_r)
    gap = Keyword.get(opts, :gap, 2)

    concepts
    |> Enum.reject(&(&1[:cx] == x and &1[:cy] == y))
    |> Enum.all?(fn concept ->
      cr = Map.get(concept, :r, @default_r)
      min_center_dist = r + cr + gap
      distance({x, y}, {Map.fetch!(concept, :cx), Map.fetch!(concept, :cy)}) > min_center_dist
    end)
  end

  defp distance({ax, ay}, {bx, by}) do
    :math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))
  end
end
