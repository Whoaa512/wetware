defmodule Wetware.Layout do
  @moduledoc "Spatial placement for concept regions on the 80x80 gel."

  @grid_w 80
  @grid_h 80
  @default_r 3
  @default_gap 2
  @search_radius 30

  @type concept_like :: %{
          required(:cx) => integer(),
          required(:cy) => integer(),
          optional(:r) => integer()
        }

  def find_position(anchor_concept, concepts) do
    anchor_r = Map.get(anchor_concept, :r, @default_r)
    target_r = @default_r

    candidates =
      for radius <- 1..@search_radius,
          dy <- -radius..radius,
          dx <- -radius..radius,
          max(abs(dx), abs(dy)) == radius,
          x = Map.fetch!(anchor_concept, :cx) + dx,
          y = Map.fetch!(anchor_concept, :cy) + dy,
          in_bounds?({x, y}, target_r),
          do:
            {x, y,
             distance({Map.fetch!(anchor_concept, :cx), Map.fetch!(anchor_concept, :cy)}, {x, y}),
             anchor_r}

    case Enum.sort_by(candidates, fn {_x, _y, dist, _anchor_r} -> dist end)
         |> Enum.find(fn {x, y, _dist, _anchor_r} ->
           is_empty_spot({x, y}, concepts, r: target_r)
         end) do
      {x, y, _dist, _anchor_r} -> {x, y}
      nil -> find_position_default(concepts, r: target_r)
    end
  end

  def find_position_default(concepts, opts \\ []) do
    r = Keyword.get(opts, :r, @default_r)

    for y <- r..(@grid_h - r - 1),
        x <- r..(@grid_w - r - 1),
        is_empty_spot({x, y}, concepts, r: r) do
      {x, y}
    end
    |> List.first()
    |> case do
      nil -> nil
      pos -> pos
    end
  end

  def is_empty_spot(pos, concepts, opts \\ []) do
    {x, y} = normalize_pos(pos)
    r = Keyword.get(opts, :r, @default_r)
    gap = Keyword.get(opts, :gap, @default_gap)

    in_bounds?({x, y}, r) and
      Enum.all?(concepts, fn concept ->
        cr = Map.get(concept, :r, @default_r)
        min_center_dist = r + cr + gap
        distance({x, y}, {Map.fetch!(concept, :cx), Map.fetch!(concept, :cy)}) > min_center_dist
      end)
  end

  defp normalize_pos({x, y}), do: {x, y}
  defp normalize_pos(%{x: x, y: y}), do: {x, y}

  defp in_bounds?({x, y}, r) do
    x - r >= 0 and y - r >= 0 and x + r < @grid_w and y + r < @grid_h
  end

  defp distance({ax, ay}, {bx, by}) do
    :math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))
  end
end
