defmodule Wetware.Priming do
  @moduledoc """
  Disposition hint generation from current concept activation.
  """

  @kindness_tags MapSet.new(["kindness", "care", "listening", "empathy", "gentleness"])
  @conflict_tags MapSet.new(["conflict", "tension", "emotion:conflict", "emotion:tension"])
  @overload_tags MapSet.new(["overload", "fatigue", "bandwidth", "stress"])

  @doc """
  Returns transparent, structured disposition hints.
  """
  def hints(concept_states) when is_list(concept_states) do
    by_name = Map.new(concept_states, fn {name, data} -> {name, data} end)

    [
      gentleness_hint(by_name),
      clarity_hint(by_name)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp gentleness_hint(by_name) do
    kindness = strongest_by_tags(by_name, @kindness_tags)
    conflict = strongest_by_tags(by_name, @conflict_tags)

    if kindness && conflict do
      confidence = clamp((kindness.charge + conflict.charge) / 2, 0.0, 1.0)

      %{
        id: "lean_gentle",
        orientation: "lean_toward_gentleness",
        prompt_hint: "Favor gentleness, listening, and de-escalation in tone.",
        confidence: Float.round(confidence, 4),
        sources: [
          %{concept: kindness.name, charge: Float.round(kindness.charge, 4)},
          %{concept: conflict.name, charge: Float.round(conflict.charge, 4)}
        ],
        override_key: "gentleness"
      }
    else
      nil
    end
  end

  defp clarity_hint(by_name) do
    overload = strongest_by_tags(by_name, @overload_tags)

    if overload do
      confidence = clamp(overload.charge, 0.0, 1.0)

      %{
        id: "be_concise",
        orientation: "increase_clarity_and_concision",
        prompt_hint: "Prefer short, explicit steps and reduce cognitive load.",
        confidence: Float.round(confidence, 4),
        sources: [%{concept: overload.name, charge: Float.round(overload.charge, 4)}],
        override_key: "clarity"
      }
    else
      nil
    end
  end

  defp strongest_by_tags(by_name, wanted_tags) do
    by_name
    |> Enum.map(fn {name, data} ->
      tags = data.tags || []

      if not MapSet.disjoint?(MapSet.new(tags), wanted_tags),
        do: %{name: name, charge: data.charge},
        else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(& &1.charge, fn -> nil end)
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))
end
