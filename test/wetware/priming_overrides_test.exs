defmodule Wetware.PrimingOverridesTest do
  use ExUnit.Case, async: false

  alias Wetware.PrimingOverrides

  setup do
    original_data_dir = System.get_env("WETWARE_DATA_DIR")
    tmp_dir = tmp_dir("priming_overrides")
    System.put_env("WETWARE_DATA_DIR", tmp_dir)

    on_exit(fn ->
      case original_data_dir do
        nil -> System.delete_env("WETWARE_DATA_DIR")
        value -> System.put_env("WETWARE_DATA_DIR", value)
      end

      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  test "disabled_keys/0 starts empty and deduplicates entries" do
    assert PrimingOverrides.disabled_keys() == []

    assert :ok = PrimingOverrides.set_enabled("gentleness", false)
    assert :ok = PrimingOverrides.set_enabled("gentleness", false)

    assert PrimingOverrides.disabled_keys() == ["gentleness"]
  end

  test "set_enabled/2 can re-enable a previously disabled key" do
    assert :ok = PrimingOverrides.set_enabled("directness", false)
    assert "directness" in PrimingOverrides.disabled_keys()

    assert :ok = PrimingOverrides.set_enabled("directness", true)
    refute "directness" in PrimingOverrides.disabled_keys()
  end

  defp tmp_dir(prefix) do
    path =
      Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(path)
    path
  end
end
