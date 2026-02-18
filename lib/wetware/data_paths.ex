defmodule Wetware.DataPaths do
  @moduledoc "Shared path helpers for wetware state files."

  @default_data_dir Path.expand("~/.config/wetware")

  def data_dir do
    System.get_env("WETWARE_DATA_DIR") || @default_data_dir
  end

  def concepts_path, do: Path.join(data_dir(), "concepts.json")
  def gel_state_path, do: Path.join(data_dir(), "gel_state.json")
  def pending_concepts_path, do: Path.join(data_dir(), "pending_concepts.json")
  def pruned_history_path, do: Path.join(data_dir(), "pruned_history.json")
  def priming_overrides_path, do: Path.join(data_dir(), "priming_overrides.json")

  def ensure_data_dir! do
    File.mkdir_p!(data_dir())
    :ok
  end
end
