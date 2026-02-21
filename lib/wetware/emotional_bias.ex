defmodule Wetware.EmotionalBias do
  alias Wetware.Util
  @moduledoc """
  Bias model that lets warm emotional state modulate imprint response.

  Current rule:
  - Warm conflict/tension dampens assertive concepts
  - Warm conflict/tension amplifies care/listening concepts
  """

  alias Wetware.{Concept, Util}

  @conflict_tags MapSet.new(["emotion:conflict", "conflict", "tension", "emotion:tension"])
  @assertive_tags MapSet.new(["assertive", "push", "confront", "dominance"])
  @care_tags MapSet.new(["care", "listening", "repair", "empathy", "support"])

  @spec strength_multiplier(String.t()) :: float()
  def strength_multiplier(concept_name) do
    conflict = conflict_intensity()
    do_strength_multiplier(concept_name, conflict)
  end

  @spec strength_multipliers([String.t()]) :: %{optional(String.t()) => float()}
  def strength_multipliers(concept_names) when is_list(concept_names) do
    conflict = conflict_intensity()

    concept_names
    |> Enum.map(fn name -> {name, do_strength_multiplier(name, conflict)} end)
    |> Map.new()
  end

  defp do_strength_multiplier(concept_name, conflict) do
    if conflict <= 0.05 do
      1.0
    else
      tags =
        concept_name
        |> safe_tags()
        |> MapSet.new()

      cond do
        has_any?(tags, @assertive_tags) ->
          Util.clamp(1.0 - 0.5 * conflict, 0.4, 1.0)

        has_any?(tags, @care_tags) ->
          Util.clamp(1.0 + 0.5 * conflict, 1.0, 1.6)

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
    Util.safe_exit(
      fn ->
        case Concept.info(name) do
          %{tags: tags} when is_list(tags) -> tags
          _ -> []
        end
      end,
      []
    )
  end

  defp safe_charge(name), do: Util.safe_exit(fn -> Concept.charge(name) end, 0.0)

  defp has_any?(a, b), do: not MapSet.disjoint?(a, b)

  defp average([]), do: 0.0
  defp average(values), do: Enum.sum(values) / length(values)
end
