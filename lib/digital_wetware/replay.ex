defmodule DigitalWetware.Replay do
  @moduledoc """
  Replay Nova's memory through the gel — speed-run history.

  Reads daily log files chronologically, extracts concept mentions,
  imprints them with proportional strength, runs decay between days,
  and dreams after each day.
  """

  alias DigitalWetware.{Concept, Gel}

  @doc """
  Run the full replay over a memory directory.

  Reads YYYY-MM-DD.md files, processes them chronologically,
  and saves state at the end.
  """
  def run(memory_dir, concepts_path, state_path) do
    # Load concept definitions for tag matching
    concept_defs = load_concept_defs(concepts_path)

    # Find and sort daily log files
    files =
      memory_dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.filter(&(Regex.match?(~r/\d{4}-\d{2}-\d{2}\.md$/, &1)))
      |> Enum.sort()

    if files == [] do
      IO.puts("❌ No daily log files (YYYY-MM-DD.md) found in #{memory_dir}")
      :error
    else
      IO.puts("")
      IO.puts(IO.ANSI.cyan() <> "═══ 🧬 Wetware Replay ═══" <> IO.ANSI.reset())
      IO.puts("  Memory dir: #{memory_dir}")
      IO.puts("  Log files:  #{length(files)}")
      IO.puts("  Concepts:   #{map_size(concept_defs)}")
      IO.puts(IO.ANSI.cyan() <> "══════════════════════════" <> IO.ANSI.reset())
      IO.puts("")

      total_days = length(files)
      dream_echoes = run_days(files, concept_defs, total_days)

      # Final summary
      print_summary(dream_echoes, state_path)
    end
  end

  defp run_days(files, concept_defs, total_days) do
    {_last_date, dream_echoes} =
      files
      |> Enum.with_index(1)
      |> Enum.reduce({nil, []}, fn {file, day_num}, {prev_date, echoes_acc} ->
        date = file |> Path.basename(".md")
        current_date = Date.from_iso8601!(date)

        # 1. Time gap decay
        gap_days =
          case prev_date do
            nil -> 0
            d -> Date.diff(current_date, d)
          end

        # Cap decay at 100 steps — beyond that, everything has fully decayed anyway
        # Each step does full grid propagation + decay, so 100 is plenty
        decay_steps = min(gap_days * 10, 100)

        if decay_steps > 0 do
          Gel.step(decay_steps)
          # Decay associations proportionally (1 decay per 10 gel steps)
          assoc_decay = max(1, div(decay_steps, 10))
          DigitalWetware.Associations.decay(assoc_decay)
        end

        # 2. Extract concepts from text
        {:ok, text} = File.read(file)
        text_lower = String.downcase(text)
        raw_matches = extract_concepts(text_lower, concept_defs)

        # Normalize: if many concepts fire, dilute each one.
        # A focused day (3-5 concepts) should imprint harder per-concept
        # than a scattered day (25+ concepts). Sqrt gives gentle dilution.
        num_matched = length(raw_matches)
        dilution = if num_matched > 6, do: :math.sqrt(6 / num_matched), else: 1.0

        matches = raw_matches

        # 3. Imprint matched concepts
        matched_names = Enum.map(matches, fn {name, _} -> name end)
        Enum.each(matches, fn {name, count} ->
          strength = mention_strength(count) * dilution
          Concept.stimulate(name, strength)
        end)

        # Record co-activation for all concepts mentioned together
        if length(matched_names) >= 2 do
          DigitalWetware.Associations.co_activate(matched_names)
        end

        # Run 5 propagation steps after imprinting
        if matches != [], do: Gel.step(5)

        # 4. Dream — 3 steps
        dream_result = dream_steps(3)

        # 5. Print progress
        concepts_str =
          matches
          |> Enum.sort_by(fn {_, c} -> -c end)
          |> Enum.map(fn {name, count} -> "#{name}(#{count})" end)
          |> Enum.join(", ")

        active_str =
          Concept.list_all()
          |> Enum.map(fn name -> {name, Concept.charge(name)} end)
          |> Enum.filter(fn {_, c} -> c > 0.05 end)
          |> Enum.sort_by(fn {_, c} -> -c end)
          |> Enum.take(6)
          |> Enum.map(fn {name, c} -> "#{name} #{Float.round(c, 2)}" end)
          |> Enum.join(", ")

        IO.puts("📅 #{date} (day #{day_num}/#{total_days}, gap: #{gap_days}d, decay: #{decay_steps} steps)")

        if concepts_str != "" do
          IO.puts("   Concepts: #{concepts_str}")
        else
          IO.puts("   Concepts: (none matched)")
        end

        if active_str != "" do
          IO.puts("   Active: #{active_str}")
        end

        IO.puts("")

        new_echoes =
          if dream_result.echoes != [] do
            [{date, dream_result.echoes} | echoes_acc]
          else
            echoes_acc
          end

        {current_date, new_echoes}
      end)

    Enum.reverse(dream_echoes)
  end

  defp dream_steps(steps) do
    p = Gel.params()

    before_charges =
      Concept.list_all()
      |> Enum.map(fn name -> {name, Concept.charge(name)} end)
      |> Map.new()

    Enum.each(1..steps, fn _ ->
      x = :rand.uniform(p.width) - 1
      y = :rand.uniform(p.height) - 1
      r = :rand.uniform(3) + 1
      Gel.stimulate_region(x, y, r, 0.3)
      Gel.step()
    end)

    after_charges =
      Concept.list_all()
      |> Enum.map(fn name -> {name, Concept.charge(name)} end)
      |> Map.new()

    echoes =
      Concept.list_all()
      |> Enum.map(fn name ->
        before = Map.get(before_charges, name, 0.0)
        after_c = Map.get(after_charges, name, 0.0)
        delta = after_c - before
        {name, Float.round(delta, 4)}
      end)
      |> Enum.filter(fn {_name, delta} -> delta > 0.001 end)
      |> Enum.sort_by(fn {_name, delta} -> -delta end)

    %{echoes: echoes}
  end

  defp extract_concepts(text_lower, concept_defs) do
    concept_defs
    |> Enum.map(fn {name, tags} ->
      # Count name mentions (match hyphenated and space-separated)
      name_pattern = name |> String.replace("-", "[- ]")
      name_count = count_matches(text_lower, name_pattern)

      # Count tag mentions — but only meaningful tags
      # Skip very short/generic tags that cause false positives
      skip_tags = ~w(ai app build art care home x cli pan list gel zero nova fti)
      tag_count =
        tags
        |> Enum.reject(fn tag -> tag in skip_tags or String.length(tag) <= 2 end)
        |> Enum.map(fn tag ->
          if String.length(tag) <= 4 do
            count_matches(text_lower, "\\b#{Regex.escape(tag)}\\b")
          else
            count_matches(text_lower, Regex.escape(tag))
          end
        end)
        |> Enum.sum()

      total = name_count + tag_count
      {name, total}
    end)
    |> Enum.filter(fn {_, count} -> count > 0 end)
  end

  defp count_matches(text, pattern) do
    case Regex.compile(pattern, "i") do
      {:ok, regex} ->
        Regex.scan(regex, text) |> length()

      _ ->
        0
    end
  end

  # Logarithmic strength: diminishing returns on mention count.
  # 1 mention = baseline, 10+ = max. The jump from 1→3 matters more than 30→100.
  defp mention_strength(count) when count >= 10, do: 1.0
  defp mention_strength(count) when count >= 5, do: 0.85
  defp mention_strength(count) when count >= 3, do: 0.7
  defp mention_strength(count) when count >= 2, do: 0.5
  defp mention_strength(count) when count >= 1, do: 0.35
  defp mention_strength(_), do: 0.0

  defp load_concept_defs(concepts_path) do
    {:ok, data} = File.read(concepts_path)
    {:ok, %{"concepts" => concepts}} = Jason.decode(data)

    concepts
    |> Enum.map(fn {name, info} -> {name, info["tags"] || []} end)
    |> Map.new()
  end

  defp print_summary(dream_echoes, state_path) do
    step_count = Gel.step_count()

    IO.puts(IO.ANSI.cyan() <> "═══ 🧬 Replay Complete ═══" <> IO.ANSI.reset())
    IO.puts("  Total steps: #{step_count}")
    IO.puts("")

    # Active concepts
    all_concepts =
      Concept.list_all()
      |> Enum.map(fn name -> {name, Concept.charge(name)} end)
      |> Enum.sort_by(fn {_, c} -> -c end)

    active = Enum.filter(all_concepts, fn {_, c} -> c > 0.1 end)
    crystallized = Enum.filter(all_concepts, fn {_, c} -> c > 0.5 end)

    if crystallized != [] do
      IO.puts("  💎 CRYSTALLIZED:")
      Enum.each(crystallized, fn {name, c} ->
        bar = String.duplicate("█", trunc(c * 30))
        IO.puts("    #{String.pad_trailing(name, 25)} #{bar} #{Float.round(c, 3)}")
      end)
      IO.puts("")
    end

    if active != [] do
      IO.puts("  ⚡ ACTIVE:")
      Enum.each(active, fn {name, c} ->
        bar = String.duplicate("█", trunc(c * 30))
        IO.puts("    #{String.pad_trailing(name, 25)} #{bar} #{Float.round(c, 3)}")
      end)
      IO.puts("")
    end

    # Top associations (from co-activation tracker)
    IO.puts("  🔗 TOP ASSOCIATIONS:")
    top_concepts = active |> Enum.take(5) |> Enum.map(fn {name, _} -> name end)

    Enum.each(top_concepts, fn name ->
      assocs = DigitalWetware.Associations.get(name, 3)

      if assocs != [] do
        assoc_str =
          assocs
          |> Enum.map(fn {aname, w} -> "#{aname}(#{w})" end)
          |> Enum.join(", ")

        IO.puts("    #{name} → #{assoc_str}")
      end
    end)

    IO.puts("")

    # Dream echoes summary
    if dream_echoes != [] do
      IO.puts("  🌊 DREAM ECHOES (unexpected activations):")

      # Aggregate across all days
      all_echoes =
        dream_echoes
        |> Enum.flat_map(fn {_date, echoes} -> echoes end)
        |> Enum.group_by(fn {name, _} -> name end)
        |> Enum.map(fn {name, entries} ->
          total = entries |> Enum.map(fn {_, d} -> d end) |> Enum.sum()
          count = length(entries)
          {name, Float.round(total, 3), count}
        end)
        |> Enum.sort_by(fn {_, total, _} -> -total end)
        |> Enum.take(10)

      Enum.each(all_echoes, fn {name, total, count} ->
        IO.puts("    #{name}: +#{total} (#{count} days)")
      end)

      IO.puts("")
    end

    # Save state
    DigitalWetware.Persistence.save(state_path)
    IO.puts("  ✓ State saved to #{state_path}")

    # Print full briefing
    IO.puts("")
    DigitalWetware.Resonance.print_briefing()
  end
end
