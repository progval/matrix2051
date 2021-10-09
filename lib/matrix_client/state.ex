defmodule Matrix2051.MatrixClient.State do
  @moduledoc """
    Stores the state of a Matrix client (access token, joined rooms, ...)
  """

  # channel_sync_callbacks is a map from channel names to lists of callbacks to run
  # when a room with that channel name is completely synced
  defstruct [:rooms, channel_sync_callbacks: Map.new()]

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

      remaining_callbacks = state.channel_sync_callbacks

      remaining_callbacks =
        if room.synced do
          {room_callbacks, remaining_callbacks} =
            Map.pop(remaining_callbacks, room.canonical_alias, [])

          room_callbacks |> Enum.map(fn cb -> cb.(room_id, room) end)
          remaining_callbacks
        else
          remaining_callbacks
        end

      {old_canonical_alias,
       %{
         state
         | rooms: Map.put(state.rooms, room_id, room),
           channel_sync_callbacks: remaining_callbacks
       }}
    end)
  end

  def room_canonical_alias(pid, room_id) do
    Agent.get(pid, fn state -> Map.get(state.rooms, room_id, @emptyroom).canonical_alias end)
  end

  @doc """
    Adds a member to the room and returns true iff it was already there
  """
  def room_member_add(pid, room_id, userid) do
    Agent.get_and_update(pid, fn state ->
      room = Map.get(state.rooms, room_id, @emptyroom)

      if MapSet.member?(room.members, userid) do
        {true, state}
      else
        room = %{room | members: MapSet.put(room.members, userid)}
        {false, %{state | rooms: Map.put(state.rooms, room_id, room)}}
      end
    end)
  end

  def room_members(pid, room_id) do
    Agent.get(pid, fn state -> Map.get(state.rooms, room_id, @emptyroom).members end)
  end

  def set_room_name(pid, room_id, name) do
    update_room(pid, room_id, fn room -> %{room | name: name} end)
  end

  def room_name(pid, room_id) do
    Agent.get(pid, fn state -> Map.get(state.rooms, room_id, @emptyroom).name end)
  end

  def set_room_topic(pid, room_id, topic) do
    update_room(pid, room_id, fn room -> %{room | topic: topic} end)
  end

  def room_topic(pid, room_id) do
    Agent.get(pid, fn state -> Map.get(state.rooms, room_id, @emptyroom).topic end)
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

  @doc """
    Returns the {room_id, room} corresponding the to given channel name, or nil.
  """
  def room_from_irc_channel(pid, channel) do
    Agent.get(pid, fn state ->
      _room_from_irc_channel(state, channel)
    end)
  end

  defp _room_from_irc_channel(state, channel) do
    state.rooms
    |> Map.to_list()
    |> Enum.find_value(fn {room_id, room} ->
      if room.canonical_alias == channel || room_id == channel do
        {room_id, room}
      else
        nil
      end
    end)
  end

  @doc """
    Takes a callback to run as soon as the room matching the given channel name
    is completely synced.
  """
  def queue_on_channel_sync(pid, channel, callback) do
    Agent.update(pid, fn state ->
      case _room_from_irc_channel(state, channel) do
        {room_id, %Matrix2051.Matrix.RoomState{synced: true} = room} ->
          # We already have the room, call immediately
          callback.(room_id, room)
          state

        _ ->
          # We don't have the member list yet, queue it.
          %{
            state
            | channel_sync_callbacks:
                Map.put(state.channel_sync_callbacks, channel, [
                  callback | Map.get(state.channel_sync_callbacks, channel, [])
                ])
          }
      end
    end)
  end

  @doc """
    Updates the state to mark a room is completely synced, and runs all callbacks
    that were waiting on it being synced.
  """
  def mark_synced(pid, room_id) do
    Agent.update(pid, fn state ->
      room = Map.get(state.rooms, room_id, @emptyroom)
      room = %{room | synced: true}
      remaining_callbacks = state.channel_sync_callbacks

      # Run callbacks registered for the room_id itself
      {room_callbacks, remaining_callbacks} = Map.pop(remaining_callbacks, room_id, [])
      room_callbacks |> Enum.map(fn cb -> cb.(room_id, room) end)

      # Run callbacks registered for the canonical alias
      remaining_callbacks =
        case room.canonical_alias do
          nil ->
            remaining_callbacks

          _ ->
            {room_callbacks, remaining_callbacks} =
              Map.pop(remaining_callbacks, room.canonical_alias, [])

            room_callbacks |> Enum.map(fn cb -> cb.(room_id, room) end)
            remaining_callbacks
        end

      %{
        state
        | rooms: Map.put(state.rooms, room_id, room),
          channel_sync_callbacks: remaining_callbacks
      }
    end)
  end
end
