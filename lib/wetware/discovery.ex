defmodule Wetware.Discovery do
  @moduledoc "Concept discovery and graduation from recurring text terms."

  alias Wetware.{Concept, DataPaths, Resonance}

  @default_hit_threshold 5
  @default_session_threshold 3
  @default_radius 3

  @stopwords MapSet.new(~w(
    a an and are as at be been being by can could did do does for from had has have
    he her hers him his i if in into is it its just like may might must my no not of
    on or our ours she should so some such than that the their theirs them then there
    these they this those to too was we were what when where which who why will with
    would you your yours about after also because before between during each more most
    much only other over under up down out again further once while than
  ))

  @doc "Scan text for recurring unrecognized terms and update pending state."
  def scan(text) when is_binary(text) do
    DataPaths.ensure_data_dir!()
    session_id = session_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    concepts = concepts_index()
    pending_terms = load_pending()["terms"]

    known_mentions = match_known_concepts(text, concepts)
    known_set = MapSet.new(Map.keys(known_mentions))

    recurring =
      text
      |> extract_candidates()
      |> Enum.filter(fn {_term, count} -> count >= 2 end)
      |> Enum.reject(fn {term, _count} -> known_term?(term, concepts) end)

    new_terms =
      Enum.reduce(recurring, pending_terms, fn {term, count}, acc ->
        update_pending_term(acc, term, count, session_id, now, known_set)
      end)

    state = %{"terms" => new_terms}
    save_pending(state)

    recurring
    |> Enum.map(fn {term, count} ->
      entry = Map.get(new_terms, term, %{})

      %{
        term: term,
        new_hits: count,
        total_hits: Map.get(entry, "count", count),
        sessions: map_size(Map.get(entry, "sessions", %{}))
      }
    end)
    |> Enum.sort_by(&{-&1.total_hits, &1.term})
  end

  @doc "List pending terms with counts and session info."
  def pending do
    load_pending()["terms"]
    |> Enum.map(fn {term, entry} ->
      sessions = Map.get(entry, "sessions", %{})

      %{
        term: term,
        count: Map.get(entry, "count", 0),
        session_count: map_size(sessions),
        sessions:
          sessions
          |> Enum.map(fn {sid, data} ->
            %{
              id: sid,
              hits: Map.get(data, "hits", 0),
              seen_at: Map.get(data, "seen_at"),
              known_concepts: Map.get(data, "known_concepts", [])
            }
          end)
          |> Enum.sort_by(& &1.id),
        cooccurrence: Map.get(entry, "cooccurrence", %{})
      }
    end)
    |> Enum.sort_by(fn item -> {-item.count, -item.session_count, item.term} end)
  end

  @doc "Promote a pending term to a full concept."
  def graduate(term, opts \\ []) do
    DataPaths.ensure_data_dir!()

    hit_threshold = Keyword.get(opts, :hit_threshold, @default_hit_threshold)
    session_threshold = Keyword.get(opts, :session_threshold, @default_session_threshold)
    radius = Keyword.get(opts, :r, @default_radius)

    pending_state = load_pending()
    terms = Map.get(pending_state, "terms", %{})

    with {:ok, entry} <- fetch_pending_term(terms, term),
         :ok <- enforce_thresholds(entry, hit_threshold, session_threshold),
         :ok <- ensure_not_existing_concept(term) do
      concepts = current_concepts()
      tags = make_tags(term)

      anchor = pick_anchor(entry, tags, concepts)

      with {:ok, concept} <-
             Resonance.add_concept(
               %Concept{name: term, r: radius, tags: tags},
               concepts_path: DataPaths.concepts_path()
             ) do
        updated_terms = Map.delete(terms, term)
        save_pending(%{"terms" => updated_terms})

        {:ok,
         %{
           concept: concept,
           anchor: if(anchor, do: anchor.name, else: nil),
           pending_hits: Map.get(entry, "count", 0),
           pending_sessions: map_size(Map.get(entry, "sessions", %{}))
         }}
      end
    end
  end

  @doc "Graduate all terms that pass thresholds."
  def graduate_all(opts \\ []) do
    hit_threshold = Keyword.get(opts, :hit_threshold, @default_hit_threshold)
    session_threshold = Keyword.get(opts, :session_threshold, @default_session_threshold)

    pending()
    |> Enum.filter(fn item ->
      item.count >= hit_threshold and item.session_count >= session_threshold
    end)
    |> Enum.map(fn item -> {item.term, graduate(item.term, opts)} end)
  end

  defp update_pending_term(terms, term, count, session_id, now, known_set) do
    entry = Map.get(terms, term, %{})
    sessions = Map.get(entry, "sessions", %{})
    session_data = Map.get(sessions, session_id, %{})

    session_hits = Map.get(session_data, "hits", 0) + count

    known_concepts =
      session_data
      |> Map.get("known_concepts", [])
      |> MapSet.new()
      |> MapSet.union(known_set)
      |> Enum.sort()

    updated_sessions =
      Map.put(sessions, session_id, %{
        "hits" => session_hits,
        "seen_at" => now,
        "known_concepts" => known_concepts
      })

    co = Map.get(entry, "cooccurrence", %{})

    updated_co =
      Enum.reduce(known_set, co, fn concept_name, acc ->
        Map.update(acc, concept_name, count, &(&1 + count))
      end)

    updated_entry =
      entry
      |> Map.put("count", Map.get(entry, "count", 0) + count)
      |> Map.put("sessions", updated_sessions)
      |> Map.put("cooccurrence", updated_co)
      |> Map.put("last_seen_at", now)

    Map.put(terms, term, updated_entry)
  end

  defp fetch_pending_term(terms, term) do
    case Map.fetch(terms, normalize_term(term)) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_pending}
    end
  end

  defp enforce_thresholds(entry, hit_threshold, session_threshold) do
    count = Map.get(entry, "count", 0)
    sessions = map_size(Map.get(entry, "sessions", %{}))

    if count >= hit_threshold and sessions >= session_threshold do
      :ok
    else
      {:error, {:below_threshold, %{count: count, sessions: sessions}}}
    end
  end

  defp ensure_not_existing_concept(term) do
    if term in Concept.list_all() do
      {:error, :already_exists}
    else
      :ok
    end
  end

  defp pick_anchor(entry, tags, concepts) do
    co = Map.get(entry, "cooccurrence", %{})

    by_cooccurrence =
      co
      |> Enum.sort_by(fn {_name, score} -> -score end)
      |> Enum.find_value(fn {name, _score} -> Enum.find(concepts, &(&1.name == name)) end)

    by_cooccurrence || anchor_by_tag_overlap(tags, concepts)
  end

  defp anchor_by_tag_overlap(tags, concepts) do
    tag_set = MapSet.new(tags)

    concepts
    |> Enum.map(fn concept ->
      overlap = MapSet.size(MapSet.intersection(tag_set, MapSet.new(concept.tags || [])))
      {concept, overlap}
    end)
    |> Enum.filter(fn {_concept, overlap} -> overlap > 0 end)
    |> Enum.sort_by(fn {_concept, overlap} -> -overlap end)
    |> List.first()
    |> case do
      nil -> nil
      {concept, _} -> concept
    end
  end

  defp match_known_concepts(text, concepts) do
    lowered = String.downcase(text)

    concepts
    |> Enum.map(fn concept ->
      terms = [concept.name | concept.tags]

      score =
        terms
        |> Enum.map(&count_phrase(lowered, &1))
        |> Enum.sum()

      {concept.name, score}
    end)
    |> Enum.filter(fn {_name, score} -> score > 0 end)
    |> Map.new()
  end

  defp extract_candidates(text) do
    tokens =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\-\s]/u, " ")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    ngram_counts(tokens, 3)
    |> Enum.reject(fn {term, _count} -> skip_candidate?(term) end)
  end

  defp ngram_counts(tokens, max_n) do
    singles =
      tokens
      |> Enum.reject(&MapSet.member?(@stopwords, &1))
      |> Enum.reduce(%{}, fn token, acc -> Map.update(acc, token, 1, &(&1 + 1)) end)

    multi =
      for n <- 2..max_n,
          idx <- 0..(length(tokens) - n),
          slice = Enum.slice(tokens, idx, n),
          Enum.all?(slice, fn t -> not MapSet.member?(@stopwords, t) end),
          term = Enum.join(slice, " "),
          reduce: %{} do
        acc -> Map.update(acc, term, 1, &(&1 + 1))
      end

    Map.merge(singles, multi, fn _k, a, b -> a + b end)
  end

  defp skip_candidate?(term) do
    parts = String.split(term, " ")

    Enum.any?(parts, fn p ->
      String.length(p) < 3 or MapSet.member?(@stopwords, p)
    end)
  end

  defp known_term?(term, concepts) do
    hyphen = String.replace(term, " ", "-")

    Enum.any?(concepts, fn c ->
      c.name == term or c.name == hyphen or term in c.tags or hyphen in c.tags
    end)
  end

  defp count_phrase(text, phrase) do
    normalized = phrase |> String.downcase() |> String.replace("-", " ")

    case Regex.compile("\\b" <> Regex.escape(normalized) <> "\\b") do
      {:ok, regex} -> Regex.scan(regex, text) |> length()
      _ -> 0
    end
  end

  defp normalize_term(term) do
    term
    |> String.downcase()
    |> String.trim()
  end

  defp make_tags(term) do
    tokens =
      term
      |> String.replace("-", " ")
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)

    ([term, String.replace(term, " ", "-")] ++ tokens)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp concepts_index do
    current_concepts()
  end

  defp current_concepts do
    Concept.list_all()
    |> Enum.map(&Concept.info/1)
  end

  defp load_pending do
    path = DataPaths.pending_concepts_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, data} ->
          case Jason.decode(data) do
            {:ok, decoded} ->
              %{"terms" => normalize_terms(decoded)}

            _ ->
              %{"terms" => %{}}
          end

        _ ->
          %{"terms" => %{}}
      end
    else
      %{"terms" => %{}}
    end
  end

  defp save_pending(state) do
    path = DataPaths.pending_concepts_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(state, pretty: true))
    :ok
  end

  defp session_id do
    "session-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp normalize_terms(%{"terms" => terms}) when is_map(terms), do: terms
  defp normalize_terms(terms) when is_map(terms), do: Map.delete(terms, "terms")
  defp normalize_terms(_), do: %{}
end
