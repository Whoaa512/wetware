defmodule Mix.Tasks.Wetware.Migrate do
  @moduledoc "Convert legacy wetware state files into elixir-v3-sparse format."
  @shortdoc "Migrate v2 state to v3 sparse"

  use Mix.Task

  alias Wetware.{DataPaths, Persistence.V2Migration}

  @impl Mix.Task
  def run(args) do
    {opts, _positional, _invalid} = OptionParser.parse(args, strict: [from: :string, to: :string])

    from = Keyword.get(opts, :from, DataPaths.gel_state_path())
    to = Keyword.get(opts, :to, from)

    with {:ok, payload} <- File.read(from),
         {:ok, decoded} <- Jason.decode(payload),
         {:ok, sparse} <- to_sparse(decoded) do
      File.mkdir_p!(Path.dirname(to))
      File.write!(to, Jason.encode!(sparse, pretty: true))
      Mix.shell().info("Migrated #{from} -> #{to} (version: #{sparse["version"]})")
    else
      {:error, :unsupported} ->
        Mix.raise("Unsupported state format in #{from}. Expected v2 dense or v3 sparse.")

      {:error, reason} ->
        Mix.raise("Migration failed: #{inspect(reason)}")
    end
  end

  defp to_sparse(%{"version" => "elixir-v3-sparse"} = state), do: {:ok, state}

  defp to_sparse(%{"version" => "elixir-v2"} = state),
    do: {:ok, V2Migration.to_sparse_state(state)}

  defp to_sparse(state) when is_map(state) do
    if Map.has_key?(state, "charges") do
      {:ok, V2Migration.to_sparse_state(state)}
    else
      {:error, :unsupported}
    end
  end

  defp to_sparse(_), do: {:error, :unsupported}
end
