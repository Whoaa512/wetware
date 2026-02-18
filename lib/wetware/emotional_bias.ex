defmodule Wetware.EmotionalBias do
  @moduledoc """
  Bias model that lets warm emotional state modulate imprint response.

  Current rule:
  - Warm conflict/tension dampens assertive concepts
  - Warm conflict/tension amplifies care/listening concepts
  """

  alias Wetware.Concept

  @conflict_tags MapSet.new(["emotion:conflict", "conflict", "tension", "emotion:tension"])
  @assertive_tags MapSet.new(["assertive", "push", "confront", "dominance"])
  @care_tags MapSet.new(["care", "listening", "repair", "empathy", "support"])

  def strength_multiplier(concept_name) do
    conflict = conflict_intensity()

    if conflict <= 0.05 do
      1.0
    else
      tags =
        concept_name
        |> safe_tags()
        |> MapSet.new()

      cond do
        has_any?(tags, @assertive_tags) ->
          clamp(1.0 - 0.5 * conflict, 0.4, 1.0)

        has_any?(tags, @care_tags) ->
          clamp(1.0 + 0.5 * conflict, 1.0, 1.6)

        true ->
          1.0
      end
    end
  end

  defp conflict_intensity do
    Concept.list_all()
    |> Enum.filter(fn name ->
      name
      |> safe_tags()
      |> MapSet.new()
      |> has_any?(@conflict_tags)
    end)
    |> Enum.map(&safe_charge/1)
    |> average()
  end

  defp safe_tags(name) do
    case Concept.info(name) do
      %{tags: tags} when is_list(tags) -> tags
      _ -> []
    end
  catch
    :exit, _ -> []
  end

  defp safe_charge(name) do
    Concept.charge(name)
  catch
    :exit, _ -> 0.0
  end

  defp has_any?(a, b), do: not MapSet.disjoint?(a, b)

  defp average([]), do: 0.0
  defp average(values), do: Enum.sum(values) / length(values)

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))
end
