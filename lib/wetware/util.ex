defmodule Wetware.Util do
  @moduledoc "Shared utility helpers for clamping and safe calls."

  @spec clamp(number(), number(), number()) :: number()
  def clamp(value, low, high), do: max(low, min(high, value))

  @spec safe_exit((-> any()), any()) :: any()
  def safe_exit(fun, fallback) when is_function(fun, 0) do
    try do
      fun.()
    catch
      :exit, _ -> fallback
    end
  end
end
