defmodule Wetware.Absorb do
  @moduledoc """
  Absorb a concept file into the gel.

  Reads a markdown concept file, extracts the concept name from the heading,
  creates the concept in the gel if it doesn't exist, finds referenced
  gel concepts in the text, and imprints everything together — creating
  associations between the new concept and its references.

  More structured than auto-imprint: understands concept file layout,
  can create new concepts, and deliberately builds the association network
  from cross-references.
  """

  alias Wetware.{AutoImprint, Concept, DataPaths, Gel, Resonance}

  @default_radius 3
  @default_steps 10
  @default_strength 0.8

  @type result :: %{
          concept_name: String.t(),
          created: boolean(),
          referenced_concepts: [String.t()],
          valence: float(),
          steps: pos_integer(),
          cross_refs: [String.t()]
        }

  @doc """
  Absorb a concept file into the gel.

  Options:
    - `:steps` — gel steps to run after imprinting (default: #{@default_steps})
    - `:strength` — stimulation strength (default: #{@default_strength})
    - `:dry_run` — if true, report what would happen without modifying the gel
  """
  @spec run(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(file_path, opts \\ []) do
    steps = Keyword.get(opts, :steps, @default_steps)
    strength = Keyword.get(opts, :strength, @default_strength)
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, text} <- read_file(file_path),
         {:ok, concept_name} <- extract_concept_name(text),
         referenced <- find_referenced_concepts(text, concept_name),
         cross_refs <- extract_cross_references(text),
         valence <- AutoImprint.infer_valence(text) do
      existing = concept_exists?(concept_name)

      if dry_run do
        {:ok,
         %{
           concept_name: concept_name,
           created: not existing,
           referenced_concepts: Enum.map(referenced, fn {name, _count} -> name end),
           valence: Float.round(valence, 4),
           steps: steps,
           cross_refs: cross_refs
         }}
      else
        # Create concept if it doesn't exist
        created =
          if not existing do
            tags = build_tags(concept_name, cross_refs, referenced)

            case Resonance.add_concept(
                   %Concept{name: concept_name, r: @default_radius, tags: tags},
                   concepts_path: DataPaths.concepts_path()
                 ) do
              {:ok, _info} -> true
              {:error, _reason} -> false
            end
          else
            false
          end

        # Build the full list of concepts to co-activate
        all_concepts =
          [concept_name | Enum.map(referenced, fn {name, _} -> name end)]
          |> Enum.uniq()
          |> Enum.filter(&concept_exists?/1)

        # Imprint: stimulate all concepts together, creating associations
        if length(all_concepts) > 0 do
          Resonance.imprint(all_concepts, steps: steps, strength: strength, valence: valence)
        end

        # Extra stimulation for the primary concept (it's the subject)
        if concept_exists?(concept_name) do
          Concept.stimulate(concept_name, strength * 1.2, valence: valence)
        end

        # Run a few more steps to let resonance settle
        Gel.step(3)

        {:ok,
         %{
           concept_name: concept_name,
           created: created,
           referenced_concepts: Enum.map(referenced, fn {name, _count} -> name end),
           valence: Float.round(valence, 4),
           steps: steps,
           cross_refs: cross_refs
         }}
      end
    end
  end

  # ── Private ────────────────────────────────────────

  defp read_file(path) do
    expanded = Path.expand(path)

    if File.exists?(expanded) and File.regular?(expanded) do
      File.read(expanded)
    else
      {:error, :file_not_found}
    end
  end

  @doc false
  def extract_concept_name(text) do
    # Look for the first # heading
    case Regex.run(~r/^#\s+(.+)$/m, text) do
      [_, heading] ->
        name =
          heading
          |> String.trim()
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s\-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        if name == "" do
          {:error, :empty_concept_name}
        else
          {:ok, name}
        end

      nil ->
        {:error, :no_heading_found}
    end
  end

  defp find_referenced_concepts(text, exclude_name) do
    lowered = String.downcase(text)

    Concept.list_all()
    |> Enum.reject(fn name -> name == exclude_name end)
    |> Enum.map(fn name ->
      info = Concept.info(name)
      terms = [name | Map.get(info, :tags, [])]

      score =
        Enum.reduce(terms, 0, fn term, acc ->
          acc + count_term(lowered, term)
        end)

      {name, score}
    end)
    |> Enum.filter(fn {_name, score} -> score > 0 end)
    |> Enum.sort_by(fn {_name, score} -> -score end)
  end

  defp extract_cross_references(text) do
    # Look for a cross-references section at the end
    case Regex.run(~r/\*Cross-references?:\s*(.+)\*/is, text) do
      [_, refs_text] ->
        refs_text
        |> String.split(~r/[,;]/)
        |> Enum.map(fn ref ->
          ref
          |> String.trim()
          |> String.replace(~r/\.md$/, "")
          |> String.downcase()
          |> String.trim()
        end)
        |> Enum.reject(&(&1 == ""))

      nil ->
        []
    end
  end

  defp build_tags(concept_name, cross_refs, referenced) do
    # Tags from: cross-references, top referenced concepts, and concept name words
    name_words =
      concept_name
      |> String.split("-")
      |> Enum.reject(&(String.length(&1) < 3))

    ref_names = Enum.map(referenced |> Enum.take(5), fn {name, _} -> name end)

    (name_words ++ cross_refs ++ ref_names)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == concept_name))
    |> Enum.take(10)
  end

  defp concept_exists?(name) do
    name in Concept.list_all()
  end

  defp count_term(_text, term) when not is_binary(term) or term == "", do: 0

  defp count_term(text, term) do
    lowered = String.downcase(term)
    escaped = Regex.escape(lowered)

    case Regex.compile("\\b#{escaped}\\b", "u") do
      {:ok, regex} -> Regex.scan(regex, text) |> length()
      {:error, _} -> 0
    end
  end
end
