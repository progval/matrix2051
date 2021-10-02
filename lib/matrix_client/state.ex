defmodule Matrix2051.MatrixClient.State do
  @moduledoc """
    Stores the state of a Matrix client (access token, joined rooms, ...)
  """

  defstruct [:rooms]

  use Agent

  @emptyroom %Matrix2051.Matrix.RoomState{}

  def start_link(_opts) do
    Agent.start_link(fn -> %Matrix2051.MatrixClient.State{rooms: %{}} end)
  end

  defp update_room(pid, room_id, fun) do
    Agent.update(pid, fn state ->
      room = Map.get(state.rooms, room_id, @emptyroom)
      room = fun.(room)
      %{state | rooms: Map.put(state.rooms, room_id, room)}
    end)
  end

  def set_room_canonical_alias(pid, room_id, new_canonical_alias) do
    Agent.get_and_update(pid, fn state ->
      room = Map.get(state.rooms, room_id, @emptyroom)
      old_canonical_alias = room.canonical_alias
      room = %{room | canonical_alias: new_canonical_alias}
      {old_canonical_alias, %{state | rooms: Map.put(state.rooms, room_id, room)}}
    end)
  end

  def room_canonical_alias(pid, room_id) do
    Agent.get(pid, fn state ->
      Map.get(state.rooms, room_id, @emptyroom).canonical_alias
    end)
  end

  def set_room_name(pid, room_id, name) do
    update_room(pid, room_id, fn room -> %{room | name: name} end)
  end

  def room_name(pid, room_id) do
    Agent.get(pid, fn state ->
      Map.get(state.rooms, room_id, @emptyroom).name
    end)
  end

  def set_room_topic(pid, room_id, topic) do
    update_room(pid, room_id, fn room -> %{room | topic: topic} end)
  end

  def room_topic(pid, room_id) do
    Agent.get(pid, fn state ->
      Map.get(state.rooms, room_id, @emptyroom).topic
    end)
  end

  @doc """
    Returns the IRC channel name for the room
  """
  def room_irc_channel(pid, room_id) do
    case room_canonical_alias(pid, room_id) do
      nil -> room_id
      canonical_alias -> canonical_alias
    end
  end
end
