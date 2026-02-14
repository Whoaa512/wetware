defmodule DigitalWetware.MixProject do
  use Mix.Project

  def project do
    [
      app: :digital_wetware,
      version: "0.2.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      escript: [main_module: DigitalWetware.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {DigitalWetware.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    []
  end
end
