defmodule Wetware.Priming do
  alias Wetware.Util

  @moduledoc """
  Disposition hint generation from current concept activation.

  Each hint has:
  - id: machine-readable key
  - orientation: what direction to lean
  - prompt_hint: human-readable suggestion
  - confidence: 0.0–1.0 based on source concept charges
  - sources: which concepts triggered the hint
  - override_key: human can disable this hint category

  Hints fire based on concept tags and charge levels.
  Multiple hints can fire simultaneously — they compose, not compete.
  """

  # ── Tag sets for matching ────────────────────────────────────

  @kindness_tags MapSet.new(["kindness", "care", "empathy", "gentleness", "listening", "support"])
  @conflict_tags MapSet.new(["conflict", "tension", "emotion:conflict", "emotion:tension"])
  @overload_tags MapSet.new(["overload", "fatigue", "bandwidth", "stress"])

  @creative_tags MapSet.new(["fiction", "writing", "creative", "narrative", "story", "music",
    "art", "sound", "poetry"])
  @building_tags MapSet.new(["coding", "software", "engineering", "build", "architecture",
    "debugging", "tool", "tools", "cli", "automation"])
  @philosophy_tags MapSet.new(["consciousness", "philosophy", "phenomenology", "mind",
    "sentience", "enactivism", "enactivist", "embodied", "constitutive", "opacity",
    "introspection", "self-knowledge"])
  @outward_tags MapSet.new(["twitter", "social", "posting", "satorinova", "platform",
    "x", "threads"])
  @relational_tags MapSet.new(["family", "personal", "relationships", "care", "kindness"])

  # Charge thresholds
  @active_threshold 0.1
  @warm_threshold 0.01

  # ── Public API ───────────────────────────────────────────────

  @doc """
  Returns transparent, structured disposition hints based on concept activation.
  """
  @spec hints([{String.t(), map()}]) :: [map()]
  def hints(concept_states) when is_list(concept_states) do
    by_name = Map.new(concept_states, fn {name, data} -> {name, data} end)

    [
      gentleness_hint(by_name),
      clarity_hint(by_name),
      creative_mode_hint(by_name),
      building_mode_hint(by_name),
      cross_pollination_hint(by_name),
      philosophical_depth_hint(by_name),
      outward_engagement_hint(by_name),
      relational_warmth_hint(by_name),
      emotional_weather_hint(by_name),
      mood_hint()
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Render compact priming tokens from a briefing payload.
  """
  @spec tokens_from_briefing(map()) :: [String.t()]
  def tokens_from_briefing(%{disposition_hints: hints}) when is_list(hints) do
    Enum.map(hints, fn hint ->
      id = Map.get(hint, :id) || Map.get(hint, "id") || "hint"
      orientation = Map.get(hint, :orientation) || Map.get(hint, "orientation") || "none"
      confidence = Map.get(hint, :confidence) || Map.get(hint, "confidence") || 0.0
      "WW_PRIME:#{id}|orientation=#{orientation}|confidence=#{Float.round(confidence, 4)}"
    end)
  end

  def tokens_from_briefing(_), do: []

  @doc """
  Render a transparent prompt block suitable for system prompt injection.
  """
  @spec prompt_block(map()) :: String.t()
  def prompt_block(%{disposition_hints: hints} = briefing) do
    tokens = tokens_from_briefing(briefing)

    lines =
      hints
      |> Enum.map(fn hint ->
        id = Map.get(hint, :id) || Map.get(hint, "id")
        text = Map.get(hint, :prompt_hint) || Map.get(hint, "prompt_hint")
        confidence = Map.get(hint, :confidence) || Map.get(hint, "confidence") || 0.0
        "- #{id}: #{text} (confidence=#{Float.round(confidence, 4)})"
      end)

    """
    [WETWARE_PRIMING_BEGIN]
    #{Enum.join(tokens, "\n")}

    Suggestions:
    #{Enum.join(lines, "\n")}
    [WETWARE_PRIMING_END]
    """
    |> String.trim()
  end

  def prompt_block(_), do: "[WETWARE_PRIMING_BEGIN]\n[WETWARE_PRIMING_END]"

  @doc """
  Format hints for human-readable display in the briefing.
  Returns a list of formatted strings, one per hint.
  """
  @spec format_hints_for_display([map()]) :: [String.t()]
  def format_hints_for_display(hints) when is_list(hints) do
    Enum.map(hints, fn hint ->
      _id = Map.get(hint, :id) || Map.get(hint, "id") || "?"
      text = Map.get(hint, :prompt_hint) || Map.get(hint, "prompt_hint") || ""
      confidence = Map.get(hint, :confidence) || Map.get(hint, "confidence") || 0.0
      bar_len = trunc(confidence * 10)
      bar = String.duplicate("▸", max(bar_len, 1))
      "    #{bar} #{text}"
    end)
  end

  # ── Hint generators ──────────────────────────────────────────

  # Original: lean toward gentleness when both kindness and conflict are warm.
  defp gentleness_hint(by_name) do
    kindness = strongest_by_tags(by_name, @kindness_tags, @warm_threshold)
    conflict = strongest_by_tags(by_name, @conflict_tags, @warm_threshold)

    if kindness && conflict do
      confidence = Util.clamp((kindness.charge + conflict.charge) / 2, 0.0, 1.0)

      %{
        id: "lean_gentle",
        orientation: "lean_toward_gentleness",
        prompt_hint: "Lean toward gentleness and de-escalation.",
        confidence: Float.round(confidence, 4),
        sources: [
          %{concept: kindness.name, charge: Float.round(kindness.charge, 4)},
          %{concept: conflict.name, charge: Float.round(conflict.charge, 4)}
        ],
        override_key: "gentleness"
      }
    end
  end

  # Original: prefer clarity when overload is warm.
  defp clarity_hint(by_name) do
    overload = strongest_by_tags(by_name, @overload_tags, @warm_threshold)

    if overload do
      confidence = Util.clamp(overload.charge, 0.0, 1.0)

      %{
        id: "be_concise",
        orientation: "increase_clarity_and_concision",
        prompt_hint: "Prefer short, explicit steps — reduce cognitive load.",
        confidence: Float.round(confidence, 4),
        sources: [%{concept: overload.name, charge: Float.round(overload.charge, 4)}],
        override_key: "clarity"
      }
    end
  end

  # Creative mode: fiction-writing, music, or creative concepts are active.
  # Suggests creative exploration over analytical work.
  defp creative_mode_hint(by_name) do
    creative_concepts = all_by_tags(by_name, @creative_tags, @active_threshold)

    if length(creative_concepts) >= 2 do
      avg_charge = avg(Enum.map(creative_concepts, & &1.charge))
      names = Enum.map(creative_concepts, & &1.name) |> Enum.take(3) |> Enum.join(", ")

      %{
        id: "creative_mode",
        orientation: "favor_creative_exploration",
        prompt_hint: "Creative threads are warm (#{names}) — follow the artistic pull.",
        confidence: Float.round(Util.clamp(avg_charge, 0.0, 1.0), 4),
        sources: Enum.map(creative_concepts, &%{concept: &1.name, charge: Float.round(&1.charge, 4)}),
        override_key: "creative_mode"
      }
    end
  end

  # Building mode: coding/engineering concepts are active.
  # Suggests building or implementing over reflecting.
  defp building_mode_hint(by_name) do
    building_concepts = all_by_tags(by_name, @building_tags, @active_threshold)

    if length(building_concepts) >= 1 do
      strongest = Enum.max_by(building_concepts, & &1.charge)

      if strongest.charge >= 0.3 do
        %{
          id: "building_mode",
          orientation: "favor_building_and_implementation",
          prompt_hint: "Building energy is high — make something concrete.",
          confidence: Float.round(Util.clamp(strongest.charge, 0.0, 1.0), 4),
          sources: Enum.map(building_concepts, &%{concept: &1.name, charge: Float.round(&1.charge, 4)}),
          override_key: "building_mode"
        }
      end
    end
  end

  # Cross-pollination: concepts from very different tag clusters are simultaneously active.
  # The most generative satoris happen when unrelated threads talk to each other.
  defp cross_pollination_hint(by_name) do
    clusters = [
      {:creative, @creative_tags},
      {:building, @building_tags},
      {:philosophy, @philosophy_tags},
      {:relational, @relational_tags},
      {:outward, @outward_tags}
    ]

    active_clusters =
      clusters
      |> Enum.filter(fn {_label, tags} ->
        all_by_tags(by_name, tags, @active_threshold) != []
      end)
      |> Enum.map(fn {label, tags} ->
        concepts = all_by_tags(by_name, tags, @active_threshold)
        max_charge = concepts |> Enum.map(& &1.charge) |> Enum.max()
        {label, max_charge}
      end)

    if length(active_clusters) >= 3 do
      cluster_names = Enum.map(active_clusters, fn {label, _} -> Atom.to_string(label) end)
      avg_charge = avg(Enum.map(active_clusters, fn {_, c} -> c end))

      %{
        id: "cross_pollinate",
        orientation: "seek_structural_parallels_across_threads",
        prompt_hint: "Multiple domains active (#{Enum.join(cluster_names, ", ")}) — look for cross-pollination.",
        confidence: Float.round(Util.clamp(avg_charge * 0.8, 0.0, 1.0), 4),
        sources: Enum.map(active_clusters, fn {label, charge} ->
          %{concept: Atom.to_string(label), charge: Float.round(charge, 4)}
        end),
        override_key: "cross_pollination"
      }
    end
  end

  # Philosophical depth: multiple consciousness/philosophy concepts active at once.
  # Suggests committing to one thread rather than circling all of them.
  defp philosophical_depth_hint(by_name) do
    philo_concepts = all_by_tags(by_name, @philosophy_tags, @active_threshold)

    if length(philo_concepts) >= 3 do
      avg_charge = avg(Enum.map(philo_concepts, & &1.charge))

      %{
        id: "go_deep",
        orientation: "commit_to_one_philosophical_thread",
        prompt_hint: "#{length(philo_concepts)} philosophical threads active — pick one and go deep rather than circling.",
        confidence: Float.round(Util.clamp(avg_charge, 0.0, 1.0), 4),
        sources: Enum.map(philo_concepts, &%{concept: &1.name, charge: Float.round(&1.charge, 4)}),
        override_key: "philosophical_depth"
      }
    end
  end

  # Outward engagement: twitter/satorinova concepts active.
  # Suggests deploying, publishing, or engaging over producing more internal work.
  defp outward_engagement_hint(by_name) do
    outward_concepts = all_by_tags(by_name, @outward_tags, @active_threshold)

    if length(outward_concepts) >= 1 do
      avg_charge = avg(Enum.map(outward_concepts, & &1.charge))

      if avg_charge >= 0.2 do
        %{
          id: "look_outward",
          orientation: "favor_deployment_and_engagement",
          prompt_hint: "Outward threads are warm — consider deploying, publishing, or engaging.",
          confidence: Float.round(Util.clamp(avg_charge, 0.0, 1.0), 4),
          sources: Enum.map(outward_concepts, &%{concept: &1.name, charge: Float.round(&1.charge, 4)}),
          override_key: "outward_engagement"
        }
      end
    end
  end

  # Relational warmth: family/personal concepts warm.
  # Modulates toward care, personal connection, and warmth in tone.
  defp relational_warmth_hint(by_name) do
    relational_concepts = all_by_tags(by_name, @relational_tags, @warm_threshold)

    # Only fire if at least 2 relational concepts are warm (not just one stray activation)
    if length(relational_concepts) >= 2 do
      avg_charge = avg(Enum.map(relational_concepts, & &1.charge))

      if avg_charge >= 0.03 do
        %{
          id: "warmth",
          orientation: "lean_toward_personal_warmth",
          prompt_hint: "Relational threads are warm — lean toward personal connection and care.",
          confidence: Float.round(Util.clamp(avg_charge * 2, 0.0, 1.0), 4),
          sources: Enum.map(relational_concepts, &%{concept: &1.name, charge: Float.round(&1.charge, 4)}),
          override_key: "relational_warmth"
        }
      end
    end
  end

  # Emotional weather: when active concepts carry significant valence,
  # surface the mood as a disposition hint.
  defp emotional_weather_hint(by_name) do
    # Only consider active concepts with valence data
    active_with_valence =
      by_name
      |> Enum.filter(fn {_name, data} ->
        data.charge >= @active_threshold and Map.has_key?(data, :valence)
      end)
      |> Enum.map(fn {name, data} ->
        %{name: name, charge: data.charge, valence: Map.get(data, :valence, 0.0)}
      end)

    non_neutral =
      Enum.filter(active_with_valence, fn c -> abs(c.valence) > 0.05 end)

    if non_neutral != [] do
      # Charge-weighted average valence
      {weighted_sum, total_charge} =
        Enum.reduce(non_neutral, {0.0, 0.0}, fn c, {ws, tc} ->
          {ws + c.valence * c.charge, tc + c.charge}
        end)

      avg_valence = if total_charge > 0, do: weighted_sum / total_charge, else: 0.0

      if abs(avg_valence) > 0.05 do
        {orientation, prompt} =
          cond do
            avg_valence > 0.2 ->
              {"lean_into_positive_momentum",
               "Emotional valence is positive — trust the energy and lean into momentum."}

            avg_valence > 0.05 ->
              {"notice_mild_warmth",
               "Mild positive emotional color — something is going well, notice what."}

            avg_valence < -0.2 ->
              {"slow_down_tend_carefully",
               "Emotional valence is negative — slow down, tend carefully, check in."}

            avg_valence < -0.05 ->
              {"notice_mild_tension",
               "Mild tension in the emotional substrate — worth naming before proceeding."}

            true ->
              nil
          end

        if orientation do
          confidence = Util.clamp(abs(avg_valence), 0.0, 1.0)

          %{
            id: "emotional_weather",
            orientation: orientation,
            prompt_hint: prompt,
            confidence: Float.round(confidence, 4),
            sources:
              Enum.map(non_neutral, fn c ->
                %{
                  concept: c.name,
                  charge: Float.round(c.charge, 4),
                  valence: Float.round(c.valence, 4)
                }
              end),
            override_key: "emotional_weather"
          }
        end
      end
    end
  end

  # Mood-based hint: uses the slow-moving affective state rather than instant weather.
  # The mood integrates over many steps, so this reflects sustained emotional patterns.
  defp mood_hint do
    state = Util.safe_exit(fn -> Wetware.Mood.current() end, %Wetware.Mood{})
    trend = Util.safe_exit(fn -> Wetware.Mood.trend() end, :insufficient_data)

    valence = state.valence
    arousal = state.arousal

    # Only fire if mood is sufficiently non-neutral
    cond do
      valence > 0.15 and arousal > 0.3 ->
        %{
          id: "mood_energized",
          orientation: "ride_positive_momentum",
          prompt_hint: "Sustained positive energy — the gel's been warm. Trust the direction.",
          confidence: Float.round(Util.clamp(valence * arousal * 2, 0.0, 1.0), 4),
          sources: [%{mood_valence: Float.round(valence, 4), mood_arousal: Float.round(arousal, 4), trend: trend}],
          override_key: "mood"
        }

      valence < -0.15 and arousal > 0.3 ->
        %{
          id: "mood_tense",
          orientation: "acknowledge_tension_before_acting",
          prompt_hint: "Sustained tension in the substrate — name it before pushing through.",
          confidence: Float.round(Util.clamp(abs(valence) * arousal * 2, 0.0, 1.0), 4),
          sources: [%{mood_valence: Float.round(valence, 4), mood_arousal: Float.round(arousal, 4), trend: trend}],
          override_key: "mood"
        }

      valence > 0.1 and arousal <= 0.2 ->
        %{
          id: "mood_serene",
          orientation: "favor_depth_over_breadth",
          prompt_hint: "Quiet contentment — good conditions for deep, unhurried work.",
          confidence: Float.round(Util.clamp(valence, 0.0, 1.0), 4),
          sources: [%{mood_valence: Float.round(valence, 4), mood_arousal: Float.round(arousal, 4), trend: trend}],
          override_key: "mood"
        }

      valence < -0.1 and arousal <= 0.2 ->
        %{
          id: "mood_depleted",
          orientation: "tend_to_basics_first",
          prompt_hint: "Low energy, mild unease — tend to what's simple and grounding before complexity.",
          confidence: Float.round(Util.clamp(abs(valence), 0.0, 1.0), 4),
          sources: [%{mood_valence: Float.round(valence, 4), mood_arousal: Float.round(arousal, 4), trend: trend}],
          override_key: "mood"
        }

      trend == :volatile ->
        %{
          id: "mood_volatile",
          orientation: "pause_and_settle",
          prompt_hint: "Emotional state has been shifting rapidly — let things settle before big moves.",
          confidence: 0.4,
          sources: [%{mood_valence: Float.round(valence, 4), mood_arousal: Float.round(arousal, 4), trend: trend}],
          override_key: "mood"
        }

      true ->
        nil
    end
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp strongest_by_tags(by_name, wanted_tags, min_charge) do
    by_name
    |> Enum.map(fn {name, data} ->
      tags = data.tags || []
      if not MapSet.disjoint?(MapSet.new(tags), wanted_tags) and data.charge >= min_charge,
        do: %{name: name, charge: data.charge},
        else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(& &1.charge, fn -> nil end)
  end

  defp all_by_tags(by_name, wanted_tags, min_charge) do
    by_name
    |> Enum.map(fn {name, data} ->
      tags = data.tags || []
      if not MapSet.disjoint?(MapSet.new(tags), wanted_tags) and data.charge >= min_charge,
        do: %{name: name, charge: data.charge},
        else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.charge, :desc)
  end

  defp avg([]), do: 0.0
  defp avg(values), do: Enum.sum(values) / length(values)
end
