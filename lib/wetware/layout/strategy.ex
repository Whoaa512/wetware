defmodule Wetware.Layout.Strategy do
  @moduledoc "Behaviour for concept placement and adaptive layout decisions."

  @callback place(name :: String.t(), tags :: [String.t()], existing :: map()) :: {integer(), integer()}
  @callback should_grow?(name :: String.t(), usage :: float()) :: boolean()
  @callback should_shrink?(name :: String.t(), dormancy :: integer()) :: boolean()
end
