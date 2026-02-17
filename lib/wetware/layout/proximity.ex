defmodule Wetware.Layout.Proximity do
  @moduledoc "Default layout strategy: cluster by tag overlap, fallback to spiral search."

  @behaviour Wetware.Layout.Strategy

  @default_gap 2
  @default_r 3
  @search_radius 80

  @impl true
  def place(_name, _tags, existing) when map_size(existing) == 0 do
    {0, 0}
  end

  def place(_name, tags, existing) do
    {anchor_center, anchor_r} = pick_anchor(tags, existing)

    case find_spiral_spot(anchor_center, anchor_r, existing) do
      nil ->
        # Fallback growth line if the local area is crowded.
        x = map_size(existing) * 8
        {x, 0}

      pos ->
        pos
    end
  end

  @impl true
  def should_grow?(_name, usage), do: usage > 0.6

  @impl true
  def should_shrink?(_name, dormancy), do: dormancy > 200

  defp pick_anchor(tags, existing) do
    tag_set = MapSet.new(tags)

    existing
    |> Enum.map(fn {_name, info} ->
      overlap = MapSet.intersection(tag_set, MapSet.new(Map.get(info, :tags, []))) |> MapSet.size()
      {info, overlap}
    end)
    |> Enum.sort_by(fn {_info, overlap} -> -overlap end)
    |> List.first()
    |> case do
      nil ->
        # No overlap: anchor on the first concept.
        {_name, info} = Enum.at(existing, 0)
        {Map.fetch!(info, :center), Map.get(info, :r, @default_r)}

      {info, _overlap} ->
        {Map.fetch!(info, :center), Map.get(info, :r, @default_r)}
    end
  end

  defp find_spiral_spot({ax, ay}, anchor_r, existing) do
    target_r = @default_r

    candidates =
      for radius <- 1..@search_radius,
          dy <- -radius..radius,
          dx <- -radius..radius,
          max(abs(dx), abs(dy)) == radius,
          do: {ax + dx, ay + dy, radius, anchor_r}

    Enum.find_value(candidates, fn {x, y, _radius, _anchor_r} ->
      if empty_spot?({x, y}, target_r, existing), do: {x, y}, else: nil
    end)
  end

  defp empty_spot?({x, y}, r, existing) do
    Enum.all?(existing, fn {_name, info} ->
      {cx, cy} = Map.fetch!(info, :center)
      cr = Map.get(info, :r, @default_r)
      min_center_dist = r + cr + @default_gap
      distance({x, y}, {cx, cy}) > min_center_dist
    end)
  end

  defp distance({ax, ay}, {bx, by}) do
    :math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))
  end
end
