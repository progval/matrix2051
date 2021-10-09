defmodule Matrix2051.Matrix.RoomState do
  @moduledoc """
    Stores the state of a Matrix client (access token, joined rooms, ...)
  """

  defstruct [:canonical_alias, :name, :topic, members: MapSet.new(), synced: false]
end
