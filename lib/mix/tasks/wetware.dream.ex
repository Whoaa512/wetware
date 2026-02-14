defmodule Mix.Tasks.Wetware.Dream do
  @moduledoc "Run dream mode — random low-level stimulation."
  @shortdoc "Dream mode"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    DigitalWetware.boot()

    {opts, _, _} =
      OptionParser.parse(args, strict: [steps: :integer, intensity: :float])

    dream_opts =
      []
      |> then(fn o -> if opts[:steps], do: Keyword.put(o, :steps, opts[:steps]), else: o end)
      |> then(fn o ->
        if opts[:intensity], do: Keyword.put(o, :intensity, opts[:intensity]), else: o
      end)

    DigitalWetware.dream(dream_opts)
    DigitalWetware.print_briefing()
  end
end
