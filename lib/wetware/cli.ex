defmodule Wetware.CLI do
  @moduledoc "CLI entrypoint for the wetware binary."

  alias Wetware.{DataPaths, Discovery, Pruning, Resonance, Viz}

  # Embed default concepts at compile time so init works from the escript
  @default_concepts File.read!(
                      Path.expand("example/concepts.json", __DIR__ |> Path.join("../.."))
                    )

  def main(argv) do
    Application.ensure_all_started(:wetware)

    # Handle init before full boot — it scaffolds the data dir
    case argv do
      ["init", "--force" | _] ->
        cmd_init(force: true)

      ["init" | _] ->
        cmd_init()

      _ ->
        boot_and_dispatch(argv)
    end
  end

  defp boot_and_dispatch(argv) do
    DataPaths.ensure_data_dir!()
    concepts_path = DataPaths.concepts_path()
    gel_state_path = DataPaths.gel_state_path()

    Resonance.boot(concepts_path: concepts_path)

    is_replay = match?(["replay", _ | _], argv)
    if not is_replay and File.exists?(gel_state_path), do: Resonance.load(gel_state_path)

    case argv do
      ["briefing" | _] -> cmd_briefing()
      ["imprint", concepts_str | _] -> cmd_imprint(concepts_str, gel_state_path)
      ["dream" | rest] -> cmd_dream(rest, gel_state_path)
      ["replay", memory_dir | _] -> cmd_replay(memory_dir, concepts_path, gel_state_path)
      ["status" | _] -> cmd_status()
      ["concepts" | _] -> cmd_concepts()
      ["discover" | rest] -> cmd_discover(rest)
      ["prune" | rest] -> cmd_prune(rest)
      ["viz" | rest] -> cmd_viz(rest)
      ["serve" | rest] -> cmd_viz(rest)
      ["help" | _] -> cmd_help()
      [] -> cmd_help()
      _ -> IO.puts("Unknown command. Run: wetware help")
    end
  end

  defp cmd_init(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    data_dir = DataPaths.data_dir()
    concepts_path = DataPaths.concepts_path()

    already_exists = File.exists?(concepts_path)

    gel_exists = File.exists?(DataPaths.gel_state_path())

    cond do
      force ->
        # Force overwrite with starters
        File.mkdir_p!(data_dir)
        File.write!(concepts_path, @default_concepts)

        concept_count = count_concepts(concepts_path)

        IO.puts("")

        IO.puts(
          "#{IO.ANSI.green()}🧬 Wetware re-initialized with starter concepts#{IO.ANSI.reset()}"
        )

        IO.puts("  Concepts: #{concept_count}")
        IO.puts("")

      already_exists and has_concepts?(concepts_path) ->
        IO.puts("")
        IO.puts("#{IO.ANSI.green()}✓ Wetware is already initialized#{IO.ANSI.reset()}")
        IO.puts("  Data dir: #{data_dir}")

        concept_count = count_concepts(concepts_path)
        IO.puts("  Concepts: #{concept_count}")

        if gel_exists do
          IO.puts("  Gel state: saved")
        else
          IO.puts(
            "  Gel state: not yet (run #{IO.ANSI.cyan()}wetware imprint#{IO.ANSI.reset()} to start)"
          )
        end

        IO.puts("")
        IO.puts("  Run #{IO.ANSI.cyan()}wetware status#{IO.ANSI.reset()} for full details.")
        IO.puts("")

      already_exists and gel_exists and not has_concepts?(concepts_path) ->
        # concepts.json exists but is empty, while gel state exists — something went wrong
        IO.puts("")

        IO.puts(
          "#{IO.ANSI.yellow()}⚠ Concepts file is empty but gel state exists#{IO.ANSI.reset()}"
        )

        IO.puts("  Data dir: #{data_dir}")
        IO.puts("")
        IO.puts("  This usually means concepts were cleared accidentally.")
        IO.puts("  Your gel state (#{DataPaths.gel_state_path()}) is intact.")
        IO.puts("")
        IO.puts("  To restore, copy your concepts back into:")
        IO.puts("    #{concepts_path}")
        IO.puts("")
        IO.puts("  Or to start fresh with starter concepts, run:")
        IO.puts("    #{IO.ANSI.cyan()}wetware init --force#{IO.ANSI.reset()}")
        IO.puts("")

      true ->
        # Scaffold the data directory
        File.mkdir_p!(data_dir)

        # Write the starter concepts
        File.write!(concepts_path, @default_concepts)

        concept_count = count_concepts(concepts_path)

        IO.puts("")
        IO.puts("#{IO.ANSI.green()}🧬 Wetware initialized!#{IO.ANSI.reset()}")
        IO.puts("")
        IO.puts("  Data dir:  #{data_dir}")
        IO.puts("  Concepts:  #{concept_count} starter concepts loaded")
        IO.puts("")
        IO.puts("  #{IO.ANSI.bright()}What's here:#{IO.ANSI.reset()}")
        IO.puts("  #{data_dir}/concepts.json — your concept definitions")
        IO.puts("  Edit this file to add your own concepts, or use:")

        IO.puts(
          "    #{IO.ANSI.cyan()}wetware discover#{IO.ANSI.reset()} to auto-discover from text"
        )

        IO.puts("")
        IO.puts("  #{IO.ANSI.bright()}Next steps:#{IO.ANSI.reset()}")

        IO.puts(
          "    #{IO.ANSI.cyan()}wetware imprint \"coding, creativity\"#{IO.ANSI.reset()}  — stimulate concepts"
        )

        IO.puts(
          "    #{IO.ANSI.cyan()}wetware dream --steps 20#{IO.ANSI.reset()}             — let the gel find connections"
        )

        IO.puts(
          "    #{IO.ANSI.cyan()}wetware briefing#{IO.ANSI.reset()}                     — see what's resonating"
        )

        IO.puts("")
    end
  end

  defp has_concepts?(path) do
    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"concepts" => concepts}} when map_size(concepts) > 0 -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp count_concepts(path) do
    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"concepts" => concepts}} -> map_size(concepts)
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp cmd_briefing, do: Resonance.print_briefing()

  defp cmd_imprint(concepts_str, state_path) do
    concepts =
      concepts_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Resonance.imprint(concepts)
    Resonance.save(state_path)
    IO.puts("State saved")
  end

  defp cmd_dream(rest, state_path) do
    {opts, _, _} = OptionParser.parse(rest, strict: [steps: :integer])
    steps = Keyword.get(opts, :steps, 10)
    Resonance.dream(steps: steps)
    Resonance.save(state_path)
    IO.puts("State saved")
  end

  defp cmd_status do
    b = Resonance.briefing()

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "=== Wetware Status ===" <> IO.ANSI.reset())
    IO.puts("  Steps:    #{b.step_count}")
    IO.puts("  Concepts: #{b.total_concepts}")
    IO.puts("  Active:   #{length(b.active)}")
    IO.puts("  Warm:     #{length(b.warm)}")
    IO.puts("  Dormant:  #{length(b.dormant)}")

    hot_cells =
      try do
        Wetware.Gel.get_charges()
        |> Map.values()
        |> Enum.count(&(&1 > 0.5))
      rescue
        _ -> "?"
      end

    IO.puts("  Hot cells: #{hot_cells}")
    IO.puts(IO.ANSI.cyan() <> "======================" <> IO.ANSI.reset())
    IO.puts("")
  end

  defp cmd_concepts do
    Resonance.concepts_with_charges()
    |> Enum.each(fn c ->
      IO.puts(
        "#{String.pad_trailing(c.name, 24)} charge=#{Float.round(c.charge, 4)} center=(#{c.cx},#{c.cy}) r=#{c.r}"
      )
    end)
  end

  defp cmd_discover(["--pending" | _]) do
    Discovery.pending()
    |> Enum.each(fn item ->
      IO.puts("#{item.term}: hits=#{item.count} sessions=#{item.session_count}")
    end)
  end

  defp cmd_discover(["--graduate", term | _]) do
    case Discovery.graduate(term) do
      {:ok, result} ->
        anchor = if result.anchor, do: result.anchor, else: "none"
        c = result.concept
        IO.puts("graduated #{c.name} at (#{c.cx},#{c.cy}) r=#{c.r} anchor=#{anchor}")

      {:error, reason} ->
        IO.puts("graduate failed: #{inspect(reason)}")
    end
  end

  defp cmd_discover(["--graduate" | _]) do
    Discovery.graduate_all()
    |> Enum.each(fn {term, result} ->
      case result do
        {:ok, _} -> IO.puts("graduated #{term}")
        {:error, reason} -> IO.puts("skipped #{term}: #{inspect(reason)}")
      end
    end)
  end

  defp cmd_discover([input | _]) do
    text =
      if File.exists?(input) and File.regular?(input) do
        File.read!(input)
      else
        input
      end

    found = Discovery.scan(text)

    if found == [] do
      IO.puts("No new recurring terms discovered")
    else
      Enum.each(found, fn item ->
        IO.puts(
          "#{item.term}: +#{item.new_hits} (total=#{item.total_hits}, sessions=#{item.sessions})"
        )
      end)
    end
  end

  defp cmd_discover(_) do
    IO.puts("usage: wetware discover <text_or_file> | --pending | --graduate [term]")
  end

  defp cmd_prune(["--dry-run" | _]) do
    {:ok, list} = Pruning.prune_all(dry_run: true)

    if list == [] do
      IO.puts("No prune candidates")
    else
      Enum.each(list, fn c ->
        IO.puts("#{c.name}: dormant_steps=#{c.dormant_steps} charge=#{c.charge}")
      end)
    end
  end

  defp cmd_prune(["--confirm" | _]) do
    {:ok, results} = Pruning.prune_all()

    Enum.each(results, fn {name, result} ->
      case result do
        :ok -> IO.puts("pruned #{name}")
        {:error, reason} -> IO.puts("kept #{name}: #{inspect(reason)}")
      end
    end)
  end

  defp cmd_prune(_) do
    IO.puts("usage: wetware prune --dry-run | --confirm")
  end

  defp cmd_replay(memory_dir, concepts_path, state_path) do
    memory_dir = Path.expand(memory_dir)
    Wetware.Replay.run(memory_dir, concepts_path, state_path)
  end

  defp cmd_viz(rest) do
    {opts, _argv, _invalid} = OptionParser.parse(rest, strict: [port: :integer])
    port = Keyword.get(opts, :port, Viz.default_port())

    case Viz.serve(port: port) do
      :ok -> :ok
      {:error, reason} -> IO.puts("viz failed: #{inspect(reason)}")
    end
  end

  defp cmd_help do
    IO.puts("""

    #{IO.ANSI.cyan()}wetware#{IO.ANSI.reset()} - Wetware CLI

    #{IO.ANSI.bright()}USAGE:#{IO.ANSI.reset()}
      wetware <command> [options]

    #{IO.ANSI.bright()}COMMANDS:#{IO.ANSI.reset()}
      init                            Set up data dir with starter concepts
      briefing                        Show resonance briefing
      concepts                        List concepts and charge levels
      imprint \"concept1, concept2\"    Stimulate concepts
      dream [--steps N]               Run dream mode
      discover <text_or_file>         Scan for pending concepts
      discover --pending              Show pending terms
      discover --graduate             Graduate all eligible terms
      discover --graduate <term>      Graduate one term
      prune --dry-run                 Show prune candidates
      prune --confirm                 Prune dormant concepts
      replay <memory_dir>             Replay history through fresh gel
      viz [--port N]                  Serve live browser visualization
      serve [--port N]                Alias for viz
      status                          Show gel stats
      help                            This help message

    #{IO.ANSI.bright()}ENVIRONMENT:#{IO.ANSI.reset()}
      WETWARE_DATA_DIR   Path to data dir (default: ~/.config/wetware)
    """)
  end
end
