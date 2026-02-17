defmodule DigitalWetware.CLI do
  @moduledoc "CLI entrypoint for the wetware binary."

  alias DigitalWetware.Resonance

  def main(argv) do
    # Ensure the application is started
    Application.ensure_all_started(:digital_wetware)

    # Set data dir for persistence/concepts
    data_dir =
      System.get_env("WETWARE_DATA_DIR") ||
        Path.expand("~/.config/wetware")

    concepts_path = Path.join(data_dir, "concepts.json")

    # Boot resonance (loads concepts, boots gel)
    Resonance.boot(concepts_path: concepts_path)

    # Try loading saved state (skip for replay — it starts fresh)
    gel_state_path = Path.join(data_dir, "gel_state_ex.json")
    is_replay = match?(["replay", _ | _], argv)
    if !is_replay and File.exists?(gel_state_path), do: Resonance.load(gel_state_path)

    case argv do
      ["briefing" | _] -> cmd_briefing()
      ["imprint", concepts_str | _] -> cmd_imprint(concepts_str, gel_state_path)
      ["dream" | rest] -> cmd_dream(rest, gel_state_path)
      ["replay", memory_dir | _] -> cmd_replay(memory_dir, concepts_path, gel_state_path)
      ["status" | _] -> cmd_status()
      ["help" | _] -> cmd_help()
      [] -> cmd_help()
      _ -> IO.puts("Unknown command. Run: wetware help")
    end
  end

  defp cmd_briefing do
    Resonance.print_briefing()
  end

  defp cmd_imprint(concepts_str, state_path) do
    concepts =
      concepts_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Resonance.imprint(concepts)
    Resonance.save(state_path)
    IO.puts("   ✓ State saved")
  end

  defp cmd_dream(rest, state_path) do
    {opts, _, _} = OptionParser.parse(rest, strict: [steps: :integer])
    steps = Keyword.get(opts, :steps, 10)
    Resonance.dream(steps: steps)
    Resonance.save(state_path)
    IO.puts("   ✓ State saved")
  end

  defp cmd_status do
    b = Resonance.briefing()

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "═══ 🧬 Wetware Status ═══" <> IO.ANSI.reset())
    IO.puts("  Steps:    #{b.step_count}")
    IO.puts("  Concepts: #{b.total_concepts}")
    IO.puts("  Active:   #{length(b.active)}")
    IO.puts("  Warm:     #{length(b.warm)}")
    IO.puts("  Dormant:  #{length(b.dormant)}")

    crystals =
      try do
        charges = DigitalWetware.Gel.get_charges()
        charges
        |> List.flatten()
        |> Enum.count(&(&1 > 0.5))
      rescue
        _ -> "?"
      end

    IO.puts("  Hot cells: #{crystals}")
    IO.puts(IO.ANSI.cyan() <> "══════════════════════════" <> IO.ANSI.reset())
    IO.puts("")
  end

  defp cmd_replay(memory_dir, concepts_path, state_path) do
    memory_dir = Path.expand(memory_dir)
    DigitalWetware.Replay.run(memory_dir, concepts_path, state_path)
  end

  defp cmd_help do
    IO.puts("""

    #{IO.ANSI.cyan()}🧬 wetware#{IO.ANSI.reset()} — Digital Wetware CLI

    #{IO.ANSI.bright()}USAGE:#{IO.ANSI.reset()}
      wetware <command> [options]

    #{IO.ANSI.bright()}COMMANDS:#{IO.ANSI.reset()}
      briefing                    Show resonance briefing
      imprint "concept1, concept2"  Stimulate concepts
      dream [--steps N]           Run dream mode (default 10 steps)
      replay <memory_dir>         Replay history through fresh gel
      status                      Show gel stats
      help                        This help message

    #{IO.ANSI.bright()}ENVIRONMENT:#{IO.ANSI.reset()}
      WETWARE_DATA_DIR   Path to data dir (default: ~/.config/wetware)
    """)
  end
end
