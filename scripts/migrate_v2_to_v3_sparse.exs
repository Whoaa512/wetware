#!/usr/bin/env elixir

Mix.Task.run("app.start")

case System.argv() do
  [input_path, output_path] ->
    with {:ok, json} <- File.read(input_path),
         {:ok, state} <- Jason.decode(json) do
      sparse = Wetware.Persistence.V2Migration.to_sparse_state(state)
      File.write!(output_path, Jason.encode!(sparse, pretty: true))
      IO.puts("Converted #{input_path} -> #{output_path}")
    else
      {:error, reason} ->
        IO.puts("Migration failed: #{inspect(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts("Usage: elixir scripts/migrate_v2_to_v3_sparse.exs <input_v2.json> <output_v3_sparse.json>")
    System.halt(1)
end
