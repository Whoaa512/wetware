defmodule Wetware.Introspect do
  alias Wetware.Util
  @moduledoc """
  Deep self-examination of gel state.

  Goes beyond the briefing's what-is-active to reveal *why* —
  the crystallized pathways, association networks, spatial relationships,
  and dormancy patterns that shape the felt sense.
  """

  alias Wetware.{Associations, Concept, Gel, Resonance, Util}

  @doc """
  Full introspection report.
  """
  @spec report() :: map()
  def report do
    concepts = Concept.list_all()

    %{
      associations: association_network(concepts),
      crystals: crystal_bonds(concepts),
      concept_crystallization: concept_crystallization(concepts),
      neighbors: spatial_neighbors(concepts),
      dormancy: dormancy_profile(concepts),
      topology: topology_summary(),
      emotional_weather: emotional_weather(concepts)
    }
  end

  @doc """
  Top concept-to-concept associations from the semantic layer.
  These form through co-activation (imprinting together).
  """
  @spec association_network([String.t()]) :: [map()]
  def association_network(_concepts \\ []) do
    Associations.all(0.01)
    |> Enum.map(fn {a, b, weight} -> %{from: a, to: b, weight: weight} end)
    |> Enum.sort_by(& &1.weight, :desc)
  end

  @doc """
  Crystallized connections between concept regions.

  Scans cell-level neighbor weights within each concept's territory,
  looking for crystallized bonds that connect to cells owned by other concepts.
  These are the hard-wired pathways — connections that have been reinforced
  enough to resist normal decay.
  """
  @spec crystal_bonds([String.t()]) :: [map()]
  def crystal_bonds(concepts) do
    # Build a map: coord -> [concept_names] for all concept cells
    concept_cells = build_concept_cell_map(concepts)

    # For each concept, scan its cells for crystallized neighbor weights
    # that point to cells owned by different concepts
    concepts
    |> Enum.flat_map(fn name ->
      cells = safe_concept_cells(name)

      Enum.flat_map(cells, fn {x, y} ->
        case safe_cell_state({x, y}) do
          %{neighbors: neighbors} ->
            neighbors
            |> Enum.filter(fn {_offset, %{crystallized: c}} -> c end)
            |> Enum.flat_map(fn {{dx, dy}, %{weight: weight}} ->
              target = {x + dx, y + dy}
              target_owners = Map.get(concept_cells, target, [])

              target_owners
              |> Enum.reject(&(&1 == name))
              |> Enum.map(fn other ->
                {pair_key(name, other), weight}
              end)
            end)

          _ ->
            []
        end
      end)
    end)
    |> Enum.group_by(fn {pair, _w} -> pair end, fn {_pair, w} -> w end)
    |> Enum.map(fn {{a, b}, weights} ->
      %{
        from: a,
        to: b,
        crystal_count: length(weights),
        avg_weight: Float.round(Enum.sum(weights) / length(weights), 4),
        max_weight: Float.round(Enum.max(weights), 4)
      }
    end)
    |> Enum.sort_by(&(-&1.crystal_count))
  end

  @doc """
  Spatial proximity between concepts in gel space.
  Concepts that have clustered together through co-activation
  will show small distances.
  """
  @spec spatial_neighbors([String.t()]) :: [map()]
  def spatial_neighbors(concepts) do
    infos =
      concepts
      |> Enum.map(fn name ->
        case safe_concept_info(name) do
          %{cx: cx, cy: cy, r: r} -> {name, cx, cy, r}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    for {a, ax, ay, ar} <- infos,
        {b, bx, by, br} <- infos,
        a < b do
      distance = :math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))
      # Edge distance: how close the regions actually are (negative = overlapping)
      edge_distance = distance - ar - br

      %{
        a: a,
        b: b,
        center_distance: Float.round(distance, 2),
        edge_distance: Float.round(edge_distance, 2),
        overlapping: edge_distance < 0
      }
    end
    |> Enum.sort_by(& &1.center_distance)
  end

  @doc """
  Dormancy profile: how long each concept has been inactive.
  """
  @spec dormancy_profile([String.t()]) :: [map()]
  def dormancy_profile(concepts) do
    concepts
    |> Enum.map(fn name ->
      d = safe_dormancy(name)
      charge = safe_charge(name)

      %{
        name: name,
        charge: Float.round(charge, 4),
        dormant_steps: d.dormant_steps,
        last_active_step: d.last_active_step
      }
    end)
    |> Enum.sort_by(&(-&1.dormant_steps))
  end

  @doc """
  Summary of gel topology.
  """
  @spec topology_summary() :: map()
  def topology_summary do
    cells = Wetware.Gel.Index.list_cells()
    bounds = Gel.bounds()

    cell_states =
      cells
      |> Enum.map(fn {_coord, pid} -> safe_cell_state(pid) end)
      |> Enum.reject(&is_nil/1)

    concept_count = cell_states |> Enum.count(fn s -> s.kind == :concept end)
    interstitial_count = cell_states |> Enum.count(fn s -> s.kind == :interstitial end)
    axon_count = cell_states |> Enum.count(fn s -> s.kind == :axon end)

    total_crystal =
      cell_states
      |> Enum.flat_map(fn s ->
        s.neighbors
        |> Enum.filter(fn {_k, v} -> Map.get(v, :crystallized, false) end)
      end)
      |> length()

    active_count =
      cell_states
      |> Enum.count(fn s -> s.charge > 0.1 end)

    %{
      total_cells: length(cells),
      concept_cells: concept_count,
      interstitial_cells: interstitial_count,
      axon_cells: axon_count,
      active_cells: active_count,
      total_crystal_bonds: div(total_crystal, 2),
      bounds: bounds,
      step_count: Gel.step_count()
    }
  end

  @doc """
  Print a formatted introspection report to the terminal.
  """
  @spec print_report(keyword()) :: :ok
  def print_report(opts \\ []) do
    r = report()
    top_n = Keyword.get(opts, :top, 10)

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "╔══════════════════════════════════════════╗" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> "║        WETWARE INTROSPECTION            ║" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> "╚══════════════════════════════════════════╝" <> IO.ANSI.reset())
    IO.puts("")

    # Topology
    t = r.topology
    IO.puts(IO.ANSI.bright() <> "  Topology" <> IO.ANSI.reset())
    IO.puts("  Step #{t.step_count} | #{t.total_cells} cells (#{t.active_cells} active)")

    IO.puts(
      "  #{t.concept_cells} concept, #{t.interstitial_cells} interstitial, #{t.axon_cells} axon"
    )

    IO.puts("  #{t.total_crystal_bonds} crystallized bonds")
    IO.puts("")

    # Emotional weather
    ew = r.emotional_weather

    if ew.non_neutral_count > 0 do
      IO.puts(IO.ANSI.bright() <> "  Emotional Weather" <> IO.ANSI.reset())
      IO.puts(IO.ANSI.faint() <> "  Valence landscape across concepts" <> IO.ANSI.reset())

      avg_label =
        cond do
          ew.avg_valence > 0.2 -> "warm"
          ew.avg_valence > 0.05 -> "mild positive"
          ew.avg_valence < -0.2 -> "unsettled"
          ew.avg_valence < -0.05 -> "mild tension"
          true -> "neutral"
        end

      IO.puts("  Overall: #{avg_label} (avg valence=#{ew.avg_valence})")

      ew.concepts_with_valence
      |> Enum.filter(fn c -> abs(c.valence) > 0.05 end)
      |> Enum.take(top_n)
      |> Enum.each(fn c ->
        icon =
          cond do
            c.valence > 0.3 -> "☀"
            c.valence > 0.1 -> "◐"
            c.valence < -0.3 -> "◑"
            c.valence < -0.1 -> "◔"
            true -> "·"
          end

        bar_width = trunc(abs(c.valence) * 20)
        direction = if c.valence > 0, do: "▸", else: "◂"
        bar = String.duplicate(direction, bar_width)
        IO.puts("  #{icon} #{String.pad_trailing(c.name, 24)} #{bar} #{c.valence}")
      end)

      IO.puts("")
    end

    # Associations
    IO.puts(IO.ANSI.bright() <> "  Association Network" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.faint() <> "  Semantic bonds from co-activation" <> IO.ANSI.reset())

    case Enum.take(r.associations, top_n) do
      [] ->
        IO.puts("  (none)")

      assocs ->
        Enum.each(assocs, fn a ->
          bar_width = trunc(a.weight * 30)
          bar = String.duplicate("█", bar_width) <> String.duplicate("░", 30 - bar_width)
          IO.puts("  #{bar} #{a.weight}  #{a.from} ↔ #{a.to}")
        end)
    end

    IO.puts("")

    # Crystal bonds
    IO.puts(IO.ANSI.bright() <> "  Crystal Bonds" <> IO.ANSI.reset())

    IO.puts(IO.ANSI.faint() <> "  Hard-wired pathways (resist decay)" <> IO.ANSI.reset())

    case Enum.take(r.crystals, top_n) do
      [] ->
        IO.puts("  (none yet)")

      crystals ->
        Enum.each(crystals, fn c ->
          IO.puts(
            "  #{c.from} ⟷ #{c.to}  #{c.crystal_count} bonds, avg=#{c.avg_weight} max=#{c.max_weight}"
          )
        end)
    end

    IO.puts("")

    # Concept crystallization
    IO.puts(IO.ANSI.bright() <> "  Concept Consolidation" <> IO.ANSI.reset())

    IO.puts(
      IO.ANSI.faint() <> "  Internal crystallization (structural memory)" <> IO.ANSI.reset()
    )

    r.concept_crystallization
    |> Enum.filter(fn c -> c.crystal_bonds > 0 end)
    |> Enum.take(top_n)
    |> case do
      [] ->
        IO.puts("  (no crystallization yet)")

      crystals ->
        Enum.each(crystals, fn c ->
          pct = trunc(c.crystal_ratio * 100)
          bar_width = trunc(c.crystal_ratio * 20)
          bar = String.duplicate("█", bar_width) <> String.duplicate("░", 20 - bar_width)

          IO.puts(
            "  #{bar} #{String.pad_leading("#{pct}%", 4)} #{String.pad_trailing(c.name, 24)} #{c.crystal_bonds}/#{c.total_bonds} bonds, avg=#{c.avg_crystal_weight}"
          )
        end)
    end

    IO.puts("")

    # Spatial proximity
    IO.puts(IO.ANSI.bright() <> "  Spatial Proximity" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.faint() <> "  Closest concept pairs in gel space" <> IO.ANSI.reset())

    r.neighbors
    |> Enum.take(top_n)
    |> Enum.each(fn n ->
      overlap = if n.overlapping, do: " ⚡", else: ""

      IO.puts("  #{n.a} ↔ #{n.b}  dist=#{n.center_distance} edge=#{n.edge_distance}#{overlap}")
    end)

    IO.puts("")

    # Dormancy
    IO.puts(IO.ANSI.bright() <> "  Dormancy Profile" <> IO.ANSI.reset())

    IO.puts(
      IO.ANSI.faint() <> "  Most dormant concepts (steps since last active)" <> IO.ANSI.reset()
    )

    r.dormancy
    |> Enum.take(top_n)
    |> Enum.each(fn d ->
      charge_indicator =
        cond do
          d.charge > 0.1 -> IO.ANSI.green() <> "●" <> IO.ANSI.reset()
          d.charge > 0.01 -> IO.ANSI.yellow() <> "○" <> IO.ANSI.reset()
          true -> IO.ANSI.faint() <> "·" <> IO.ANSI.reset()
        end

      IO.puts(
        "  #{charge_indicator} #{String.pad_trailing(d.name, 24)} dormant=#{d.dormant_steps} charge=#{d.charge}"
      )
    end)

    IO.puts("")
  end

  @doc """
  Internal crystallization per concept.
  Shows how reinforced each concept's internal structure is —
  concepts with more crystal bonds have been activated more consistently.
  """
  @spec concept_crystallization([String.t()]) :: [map()]
  def concept_crystallization(concepts) do
    concepts
    |> Enum.map(fn name ->
      cells = safe_concept_cells(name)

      {total_bonds, crystal_bonds, total_weight, crystal_weight} =
        Enum.reduce(cells, {0, 0, 0.0, 0.0}, fn coord, {tb, cb, tw, cw} ->
          case safe_cell_state(coord) do
            %{neighbors: neighbors} ->
              Enum.reduce(neighbors, {tb, cb, tw, cw}, fn
                {_offset, %{weight: w, crystallized: true}}, {tb2, cb2, tw2, cw2} ->
                  {tb2 + 1, cb2 + 1, tw2 + w, cw2 + w}

                {_offset, %{weight: w}}, {tb2, cb2, tw2, cw2} ->
                  {tb2 + 1, cb2, tw2 + w, cw2}
              end)

            _ ->
              {tb, cb, tw, cw}
          end
        end)

      avg_weight = if total_bonds > 0, do: total_weight / total_bonds, else: 0.0

      %{
        name: name,
        total_bonds: total_bonds,
        crystal_bonds: crystal_bonds,
        crystal_ratio: if(total_bonds > 0, do: crystal_bonds / total_bonds, else: 0.0),
        avg_weight: Float.round(avg_weight, 4),
        avg_crystal_weight:
          Float.round(if(crystal_bonds > 0, do: crystal_weight / crystal_bonds, else: 0.0), 4)
      }
    end)
    |> Enum.sort_by(&(-&1.crystal_ratio))
  end

  @doc """
  Emotional weather: valence landscape across concepts.
  Shows which concepts carry positive or negative emotional charge,
  and the overall mood of the gel.
  """
  @spec emotional_weather([String.t()]) :: map()
  def emotional_weather(concepts) do
    concept_valences =
      concepts
      |> Enum.map(fn name ->
        charge = safe_charge(name)
        valence = safe_valence(name)
        %{name: name, charge: Float.round(charge, 4), valence: Float.round(valence, 4)}
      end)
      |> Enum.filter(fn c -> c.charge > 0.01 end)
      |> Enum.sort_by(&abs(&1.valence), :desc)

    non_neutral = Enum.filter(concept_valences, fn c -> abs(c.valence) > 0.05 end)

    # Charge-weighted average valence
    {weighted_sum, total_charge} =
      concept_valences
      |> Enum.filter(fn c -> c.charge > 0.1 end)
      |> Enum.reduce({0.0, 0.0}, fn c, {ws, tc} ->
        {ws + c.valence * c.charge, tc + c.charge}
      end)

    avg_valence = if total_charge > 0, do: weighted_sum / total_charge, else: 0.0

    %{
      avg_valence: Float.round(avg_valence, 4),
      non_neutral_count: length(non_neutral),
      concepts_with_valence: concept_valences,
      strongest_positive: Enum.find(concept_valences, fn c -> c.valence > 0.05 end),
      strongest_negative: Enum.find(concept_valences, fn c -> c.valence < -0.05 end)
    }
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp build_concept_cell_map(concepts) do
    Enum.reduce(concepts, %{}, fn name, acc ->
      cells = safe_concept_cells(name)

      Enum.reduce(cells, acc, fn coord, inner_acc ->
        Map.update(inner_acc, coord, [name], fn existing -> [name | existing] end)
      end)
    end)
  end

  defp safe_concept_cells(name) do
    Util.safe_exit(fn -> Gel.concept_cells(name) end, [])
  end

  defp safe_cell_state({x, y}) when is_integer(x) and is_integer(y) do
    Util.safe_exit(fn -> Wetware.Cell.get_state({x, y}) end, nil)
  end

  defp safe_cell_state(pid) when is_pid(pid) do
    Util.safe_exit(fn -> Wetware.Cell.get_state(pid) end, nil)
  end

  defp safe_concept_info(name) do
    Util.safe_exit(fn -> Concept.info(name) end, nil)
  end

  defp safe_dormancy(name) do
    Util.safe_exit(fn -> Resonance.dormancy(name) end, %{dormant_steps: 0, last_active_step: 0})
  end

  defp safe_charge(name) do
    Util.safe_exit(fn -> Concept.charge(name) end, 0.0)
  end

  defp safe_valence(name) do
    Util.safe_exit(fn -> Concept.valence(name) end, 0.0)
  end

  defp pair_key(a, b) when a <= b, do: {a, b}
  defp pair_key(a, b), do: {b, a}
end
