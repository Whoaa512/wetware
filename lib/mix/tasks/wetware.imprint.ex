defmodule Mix.Tasks.Wetware.Imprint do
  @moduledoc "Stimulate concepts in the gel substrate."
  @shortdoc "Imprint concepts"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Wetware.boot()

    {opts, positional, _} =
      OptionParser.parse(args, strict: [steps: :integer, strength: :float])

    concepts =
      positional
      |> Enum.join(" ")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if concepts == [] do
      IO.puts("Usage: mix wetware.imprint \"concept1, concept2\" [--steps N] [--strength F]")
    else
      imprint_opts =
        []
        |> then(fn o -> if opts[:steps], do: Keyword.put(o, :steps, opts[:steps]), else: o end)
        |> then(fn o ->
          if opts[:strength], do: Keyword.put(o, :strength, opts[:strength]), else: o
        end)

      Wetware.imprint(concepts, imprint_opts)
      Wetware.print_briefing()
    end
  end
end
