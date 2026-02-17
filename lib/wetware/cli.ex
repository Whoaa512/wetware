defmodule Wetware.CLI do
  @moduledoc "CLI entrypoint for the wetware binary."

  alias Wetware.{DataPaths, Discovery, Pruning, Resonance}

  def main(argv) do
    Application.ensure_all_started(:wetware)

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
      ["help" | _] -> cmd_help()
      [] -> cmd_help()
      _ -> IO.puts("Unknown command. Run: wetware help")
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
        |> List.flatten()
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

  defp cmd_help do
    IO.puts("""

    #{IO.ANSI.cyan()}wetware#{IO.ANSI.reset()} - Wetware CLI

    #{IO.ANSI.bright()}USAGE:#{IO.ANSI.reset()}
      wetware <command> [options]

    #{IO.ANSI.bright()}COMMANDS:#{IO.ANSI.reset()}
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
      status                          Show gel stats
      help                            This help message

    #{IO.ANSI.bright()}ENVIRONMENT:#{IO.ANSI.reset()}
      WETWARE_DATA_DIR   Path to data dir (default: ~/.config/wetware)
    """)
  end
end
