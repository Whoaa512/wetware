defmodule Mix.Tasks.Wetware.Briefing do
  @moduledoc "Print the current resonance briefing."
  @shortdoc "Print resonance briefing"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    DigitalWetware.boot()
    DigitalWetware.print_briefing()
  end
end
