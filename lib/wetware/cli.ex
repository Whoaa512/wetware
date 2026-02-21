defmodule Wetware.CLI do
  @moduledoc "CLI entrypoint for the wetware binary."

  alias Wetware.{
    AutoImprint,
    DataPaths,
    Discovery,
    Introspect,
    PrimingOverrides,
    Pruning,
    Resonance,
    Viz
  }

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
      ["imprint", concepts_str | rest] -> cmd_imprint(concepts_str, rest, gel_state_path)
      ["dream" | rest] -> cmd_dream(rest, gel_state_path)
      ["replay", memory_dir | _] -> cmd_replay(memory_dir, concepts_path, gel_state_path)
      ["status" | _] -> cmd_status()
      ["concepts" | _] -> cmd_concepts()
      ["introspect" | rest] -> cmd_introspect(rest)
      ["priming" | rest] -> cmd_priming(rest)
      ["discover" | rest] -> cmd_discover(rest)
      ["prune" | rest] -> cmd_prune(rest)
      ["auto-imprint", input | rest] -> cmd_auto_imprint(input, rest, gel_state_path)
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
    concepts_exists = File.exists?(concepts_path)

    cond do
      force ->
        write_empty_concepts!(data_dir, concepts_path)
        print_init_banner("re-initialized", data_dir, concepts_path)

      concepts_exists and valid_concepts_file?(concepts_path) ->
        concept_count = count_concepts(concepts_path)
        print_already_initialized(data_dir, concept_count)

      true ->
        write_empty_concepts!(data_dir, concepts_path)
        print_init_banner("initialized", data_dir, concepts_path)
    end
  end

  defp valid_concepts_file?(path) do
    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"concepts" => concepts}} when is_map(concepts) -> true
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

  defp write_empty_concepts!(data_dir, concepts_path) do
    File.mkdir_p!(data_dir)
    File.write!(concepts_path, Jason.encode!(%{"concepts" => %{}}, pretty: true))
  end

  defp print_init_banner(mode, data_dir, concepts_path) do
    IO.puts("")
    IO.puts("#{IO.ANSI.green()}🧬 Wetware #{mode}!#{IO.ANSI.reset()}")
    IO.puts("")
    IO.puts("  Data dir:  #{data_dir}")
    IO.puts("  Concepts:  0 (empty by default)")
    IO.puts("")
    IO.puts("  #{IO.ANSI.bright()}What's here:#{IO.ANSI.reset()}")
    IO.puts("  #{concepts_path} — your concept definitions")
    IO.puts("")
    IO.puts("  Add concepts manually or run:")

    IO.puts(
      "    #{IO.ANSI.cyan()}wetware discover \"text to extract concepts from\"#{IO.ANSI.reset()}"
    )

    IO.puts("")
  end

  defp print_already_initialized(data_dir, concept_count) do
    IO.puts("")
    IO.puts("#{IO.ANSI.green()}✓ Wetware is already initialized#{IO.ANSI.reset()}")
    IO.puts("  Data dir: #{data_dir}")
    IO.puts("  Concepts: #{concept_count}")
    IO.puts("")
    IO.puts("  Run #{IO.ANSI.cyan()}wetware status#{IO.ANSI.reset()} for full details.")
    IO.puts("")
  end

  defp cmd_briefing, do: Resonance.print_briefing()

  defp cmd_imprint(concepts_str, rest, state_path) do
    {opts, _, _} =
      OptionParser.parse(rest, strict: [steps: :integer, strength: :float, valence: :float])

    concepts =
      concepts_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    imprint_opts =
      []
      |> then(fn o -> if opts[:steps], do: Keyword.put(o, :steps, opts[:steps]), else: o end)
      |> then(fn o ->
        if opts[:strength], do: Keyword.put(o, :strength, opts[:strength]), else: o
      end)
      |> then(fn o ->
        if opts[:valence], do: Keyword.put(o, :valence, opts[:valence]), else: o
      end)

    Resonance.imprint(concepts, imprint_opts)
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

  defp cmd_introspect(rest) do
    {opts, _, _} = OptionParser.parse(rest, strict: [top: :integer, json: :boolean])

    if opts[:json] do
      report = Introspect.report()
      IO.puts(Jason.encode!(report, pretty: true))
    else
      top = Keyword.get(opts, :top, 10)
      Introspect.print_report(top: top)
    end
  end

  defp cmd_concepts do
    Resonance.concepts_with_charges()
    |> Enum.each(fn c ->
      IO.puts(
        "#{String.pad_trailing(c.name, 24)} charge=#{Float.round(c.charge, 4)} center=(#{c.cx},#{c.cy}) r=#{c.r}"
      )
    end)
  end

  defp cmd_priming(rest) do
    {opts, _, _} =
      OptionParser.parse(rest,
        strict: [format: :string, enable: :string, disable: :string, show_overrides: :boolean]
      )

    cond do
      opts[:enable] ->
        :ok = PrimingOverrides.set_enabled(opts[:enable], true)
        IO.puts("enabled priming override key: #{opts[:enable]}")

      opts[:disable] ->
        :ok = PrimingOverrides.set_enabled(opts[:disable], false)
        IO.puts("disabled priming override key: #{opts[:disable]}")

      opts[:show_overrides] ->
        disabled = PrimingOverrides.disabled_keys()
        IO.puts("disabled override keys: #{Enum.join(disabled, ", ")}")

      true ->
        format = Keyword.get(opts, :format, "text")
        payload = Resonance.priming_payload()

        case format do
          "json" ->
            IO.puts(Jason.encode!(payload, pretty: true))

          _ ->
            IO.puts(payload.prompt_block)
            IO.puts("")
            IO.puts("Override keys: #{Enum.join(payload.override_keys, ", ")}")
            IO.puts("Disabled overrides: #{Enum.join(payload.disabled_overrides, ", ")}")
        end
    end
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

  defp cmd_auto_imprint(input, rest, state_path) do
    {opts, _, _} =
      OptionParser.parse(rest,
        strict: [duration_minutes: :integer, depth: :integer, steps: :integer]
      )

    text =
      if File.exists?(input) and File.regular?(input) do
        File.read!(input)
      else
        input
      end

    auto_opts =
      []
      |> then(fn o ->
        if opts[:duration_minutes],
          do: Keyword.put(o, :duration_minutes, opts[:duration_minutes]),
          else: o
      end)
      |> then(fn o -> if opts[:depth], do: Keyword.put(o, :depth, opts[:depth]), else: o end)
      |> then(fn o -> if opts[:steps], do: Keyword.put(o, :steps, opts[:steps]), else: o end)

    case AutoImprint.run(text, auto_opts) do
      {:ok, result} ->
        Resonance.save(state_path)

        IO.puts("auto-imprint complete")
        IO.puts("  matched: #{length(result.matched_concepts)} concepts")
        IO.puts("  valence: #{result.valence}")
        IO.puts("  weight:  #{result.weight}")
        IO.puts("  steps:   #{result.steps}")

        if result.matched_concepts != [] do
          line =
            result.matched_concepts
            |> Enum.map(fn {name, count, strength} ->
              "#{name}(hits=#{count}, strength=#{strength})"
            end)
            |> Enum.join(", ")

          IO.puts("  concepts: #{line}")
        end

      {:error, :no_concepts_matched} ->
        IO.puts("auto-imprint skipped: no known concepts matched the provided text")
    end
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
      init                            Set up data dir with empty concepts.json
      briefing                        Show resonance briefing
      concepts                        List concepts and charge levels
      introspect [--top N] [--json]     Deep self-examination of gel state
      priming [--format json]         Generate transparent priming tokens
      priming --disable <key>         Disable a priming orientation
      priming --enable <key>          Re-enable a priming orientation
      priming --show-overrides        Show disabled override keys
      imprint \"concept1, concept2\"    Stimulate concepts (--steps/--strength/--valence)
      dream [--steps N]               Run dream mode
      discover <text_or_file>         Scan for pending concepts
      discover --pending              Show pending terms
      discover --graduate             Graduate all eligible terms
      discover --graduate <term>      Graduate one term
      auto-imprint <text_or_file>     Auto-extract concepts + valence and imprint
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
