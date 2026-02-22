defmodule Wetware.MixProject do
  use Mix.Project

  def project do
    [
      app: :wetware,
      version: "0.2.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      aliases: aliases(),
      escript: [main_module: Wetware.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Wetware.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:burrito, "~> 1.5", only: :prod, runtime: false}
    ]
  end

  defp releases do
    [
      wetware: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_aarch64: [os: :linux, cpu: :aarch64],
            darwin_x86_64: [os: :darwin, cpu: :x86_64],
            darwin_aarch64: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  defp aliases do
    []
  end
end
