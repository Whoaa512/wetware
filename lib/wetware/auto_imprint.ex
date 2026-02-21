defmodule Wetware.AutoImprint do
  alias Wetware.Util
  @moduledoc """
  Heuristic auto-imprint pipeline for conversation summaries/transcripts.

  Extracts known concepts + valence and imprints with depth/duration weighting.
  """

  alias Wetware.{Concept, Gel, Util}

  @negative_terms ~w(conflict tension hard overwhelmed blocked anxious frustrated upset drained stress)
  @positive_terms ~w(breakthrough progress clear resolved grateful calm trust aligned excited momentum)
  @precompiled_phrase_regexes (@negative_terms ++ @positive_terms)
                              |> Enum.uniq()
                              |> Map.new(fn term ->
                                {term, Regex.compile!("\\b#{Regex.escape(term)}\\b", "u")}
                              end)

  @type result :: %{
          matched_concepts: [{String.t(), integer(), float()}],
          valence: float(),
          weight: float(),
          steps: pos_integer(),
          depth: pos_integer(),
          duration_minutes: pos_integer()
        }

  @spec run(String.t(), keyword()) :: {:ok, result()} | {:error, :no_concepts_matched}
  def run(text, opts \\ []) when is_binary(text) do
    depth = clamp_int(Keyword.get(opts, :depth, 3), 1, 10)
    duration_minutes = clamp_int(Keyword.get(opts, :duration_minutes, 25), 1, 24 * 60)
    weight = depth_duration_weight(depth, duration_minutes)
    steps = clamp_int(Keyword.get(opts, :steps, round(2 + depth * 0.6)), 1, 24)
    valence = infer_valence(text)

    matches = extract_known_concepts(text)

    if matches == [] do
      {:error, :no_concepts_matched}
    else
      matched_concepts =
        matches
        |> Enum.map(fn {name, count} ->
          weighted_strength = Util.clamp(mention_strength(count) * weight, 0.05, 1.0)
          Concept.stimulate(name, weighted_strength, valence: valence)
          {name, count, Float.round(weighted_strength, 4)}
        end)

      Gel.step(steps)

      {:ok,
       %{
         matched_concepts: matched_concepts,
         valence: Float.round(valence, 4),
         weight: Float.round(weight, 4),
         steps: steps,
         depth: depth,
         duration_minutes: duration_minutes
       }}
    end
  end

  @spec depth_duration_weight(number(), number()) :: float()
  def depth_duration_weight(depth, duration_minutes) do
    depth_component = (depth - 1) / 9
    duration_component = :math.log(1 + duration_minutes) / :math.log(1 + 120)
    Util.clamp(0.35 + depth_component * 0.45 + duration_component * 0.45, 0.25, 2.0)
  end

  @spec infer_valence(String.t()) :: float()
  def infer_valence(text) do
    normalized = text |> String.downcase() |> String.replace(~r/[^a-z0-9\-\s]/u, " ")

    neg = score_terms(normalized, @negative_terms)
    pos = score_terms(normalized, @positive_terms)
    total = neg + pos

    if total == 0 do
      0.0
    else
      Util.clamp((pos - neg) / total, -1.0, 1.0)
    end
  end

  @spec extract_known_concepts(String.t()) :: [{String.t(), integer()}]
  def extract_known_concepts(text) do
    lowered = String.downcase(text)

    Concept.list_all()
    |> Enum.map(fn name ->
      info = Concept.info(name)
      terms = [name | Map.get(info, :tags, [])]
      score = Enum.reduce(terms, 0, fn term, acc -> acc + count_phrase(lowered, term) end)
      {name, score}
    end)
    |> Enum.filter(fn {_name, score} -> score > 0 end)
    |> Enum.sort_by(fn {_name, score} -> -score end)
  end

  defp count_phrase(_text, phrase) when not is_binary(phrase) or phrase == "", do: 0

  defp count_phrase(text, phrase) do
    lowered_phrase = String.downcase(phrase)

    regex =
      Map.get_lazy(@precompiled_phrase_regexes, lowered_phrase, fn ->
        escaped = Regex.escape(lowered_phrase)

        case Regex.compile("\\b#{escaped}\\b", "u") do
          {:ok, compiled} -> compiled
          {:error, _} -> nil
        end
      end)

    if regex do
      Regex.scan(regex, text) |> length()
    else
      0
    end
  end

  defp score_terms(text, terms) do
    Enum.reduce(terms, 0, fn term, acc -> acc + count_phrase(text, term) end)
  end

  defp mention_strength(count) when count >= 8, do: 1.0
  defp mention_strength(count) when count >= 5, do: 0.85
  defp mention_strength(count) when count >= 3, do: 0.7
  defp mention_strength(count) when count >= 2, do: 0.5
  defp mention_strength(count) when count >= 1, do: 0.35
  defp mention_strength(_), do: 0.0

  defp clamp_int(value, lo, hi) when is_integer(value), do: max(lo, min(hi, value))
  defp clamp_int(_, lo, _hi), do: lo
end
