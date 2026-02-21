defmodule Wetware.PrimingOverrides do
  @moduledoc """
  Human-visible override controls for disposition priming.
  """

  alias Wetware.DataPaths

  @spec disabled_keys() :: [String.t()]
  def disabled_keys do
    load()
    |> Map.get("disabled", [])
    |> Enum.uniq()
  end

  @spec set_enabled(String.t(), boolean()) :: :ok
  def set_enabled(key, enabled?) when is_binary(key) do
    state = load()
    disabled = Map.get(state, "disabled", [])

    next_disabled =
      if enabled? do
        Enum.reject(disabled, &(&1 == key))
      else
        Enum.uniq([key | disabled])
      end

    save(Map.put(state, "disabled", next_disabled))
    :ok
  end

  defp load do
    DataPaths.ensure_data_dir!()

    case File.read(DataPaths.priming_overrides_path()) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{} = state} -> state
          _ -> %{"disabled" => []}
        end

      {:error, _} ->
        %{"disabled" => []}
    end
  end

  defp save(state) do
    DataPaths.ensure_data_dir!()
    File.write!(DataPaths.priming_overrides_path(), Jason.encode!(state, pretty: true))
  end
end
