defmodule Matrix2051.MatrixClient.State do
  @moduledoc """
    Stores the state of a Matrix client (access token, joined rooms, ...)
  """

  defstruct [:rooms]

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %Matrix2051.MatrixClient.State{rooms: %{}} end)
  end

  def set_room_canonical_alias(pid, room_id, new_canonical_alias) do
    Agent.get_and_update(pid, fn state ->
      room = Map.get(state.rooms, room_id, %Matrix2051.Matrix.RoomState{})
      old_canonical_alias = room.canonical_alias
      room = %{room | canonical_alias: new_canonical_alias}
      {old_canonical_alias, %{state | rooms: Map.put(state.rooms, room_id, room)}}
    end)
  end

  def room_canonical_alias(pid, room_id) do
    Agent.get(pid, fn state ->
      Map.get(state.rooms, room_id, %Matrix2051.Matrix.RoomState{}).canonical_alias
    end)
  end
end
