defmodule Matrix2051.MatrixClient.Poller do
  @moduledoc """
    Queries the homeserver for new events; including the initial sync.
  """
  use Task, restart: :permanent

  def start_link(args) do
    Task.start_link(__MODULE__, :poll, [args])
  end

  def poll(args) do
    {sup_mod, sup_pid} = args
    loop_poll(sup_mod, sup_pid, nil)
  end

  def loop_poll(sup_mod, sup_pid, since) do
    client = sup_mod.matrix_client(sup_pid)

    case Matrix2051.MatrixClient.Client.raw_client(client) do
      nil ->
        # Wait for it to be initialized
        receive do
          :connected -> loop_poll(sup_mod, sup_pid, nil)
        end

      raw_client ->
        since = poll_one(sup_mod, sup_pid, since, raw_client)
        loop_poll(sup_mod, sup_pid, since)
    end
  end

  defp poll_one(sup_mod, sup_pid, since, raw_client) do
    query = %{
      # Completely arbitrary value.
      "timeout" => "600"
    }

    query =
      case since do
        nil -> query
        _ -> Map.put(query, "since", since)
      end

    path = "/_matrix/client/r0/sync?" <> URI.encode_query(query)

    case Matrix2051.Matrix.RawClient.get(raw_client, path) do
      {:ok, events} ->
        handle_events(sup_mod, sup_pid, events)
        events["next_batch"]
    end
  end

  defp handle_events(sup_mod, sup_pid, events) do
    IO.inspect(events)

    """
    # Preprocess events to get the new channel names early
    new_canonical_names =
      events
      |> Map.get("rooms", %{})
      |> Map.get("join", %{})
      |> Map.to_list()
      |> Enum.map(fn {room_id, room_event} ->
        room_event
        |> Map.get("state", %{})
        |> Map.get("events", [])
        |> Enum.reverse() # most recent last
        |> Enum.find_value(
          room_id,
          fn event ->
            case event["type"] do
              "m.room.canonical_alias" -> {room_id, event["content"]["alias"]}
              _ -> nil
            end
          end
        )
      end)
      # dedups in case there are multiple canonical name changes, keeps only the most recent
      |> Map.new()
      |> Enum.to_list()

    existing_channels =
      state
      |> Matrix2051.IrcConn.State.channels
      |> Enum.map(fn channel -> {channel.room_id, channel.name} end)
      |> Map.new()

    # FIXME: this has quadratic complexity because of linear iteration in 'channels'
    # every time. Use maps to fix this.
    channels =
      new_canonical_names
      |> Enum.reduce(existing_channels, fn {room_id, canonical_name}, channels ->
        case channels |> Enum.find(fn channel -> channel.room_id == room_id end) do
          nil ->
            # this is a new channel
            # TODO: join it
            new_channel = %Matrix2051.Irc.ChannelState{name: canonical_name, room_id: room_id}
            [new_channel | channels]

          channel ->
            # existing channel.
            if channel.canonical_name == channel.name do
              # name is unchanged
              channels
            else
              # TODO: part the old name and join the new one 
              new_channel = %Matrix2051.Irc.ChannelState{channel | name: canonical_name}
              [new_channel | Enum.filter(channels, fn channel -> channel.room_id != room_id end)]
            end
        end
      end)

    Matrix2051.IrcConn.State.set_channels(state, channels)
    """

    events
    |> Map.get("rooms", %{})
    |> Map.get("join", %{})
    |> Map.to_list()
    |> Enum.map(fn {room_id, event} -> handle_joined_room(sup_mod, sup_pid, room_id, event) end)

    events
    |> Map.get("rooms", %{})
    |> Map.get("leave", %{})
    |> Map.to_list()
    |> Enum.map(fn {room_id, event} -> handle_left_room(sup_mod, sup_pid, room_id, event) end)
  end

  defp handle_joined_room(sup_mod, sup_pid, room_id, room_event) do
    room_event
    |> Map.get("state", %{})
    |> Map.get("events", [])
    # oldest first
    |> Enum.reverse()
    |> Enum.map(fn event ->
      handle_state_event(sup_mod, sup_pid, room_id, event)
    end)

    room_event
    |> Map.get("timeline", %{})
    |> Map.get("events", [])
    # oldest first
    |> Enum.reverse()
    |> Enum.map(fn event ->
      handle_timeline_event(sup_mod, sup_pid, room_id, event)
    end)
  end

  defp handle_state_event(
         sup_mod,
         sup_pid,
         room_id,
         %{"type" => "m.room.canonical_alias"} = event
       ) do
    new_canonical_alias = event["content"]["alias"]
    irc_state = sup_mod.state(sup_pid)
    state = sup_mod.matrix_state(sup_pid)
    capabilities = Matrix2051.IrcConn.State.capabilities(irc_state)
    writer = sup_mod.writer(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(irc_state)

    send = fn cmd ->
      Matrix2051.IrcConn.Writer.write_command(
        writer,
        Matrix2051.Irc.Command.downgrade(cmd, capabilities)
      )
    end

    old_canonical_alias =
      Matrix2051.MatrixClient.State.set_room_canonical_alias(
        state,
        room_id,
        new_canonical_alias
      )

    # Join the new channel
    send.(%Matrix2051.Irc.Command{
      tags: %{"account" => nick},
      source: nick,
      command: "JOIN",
      params: [new_canonical_alias, nick, nick]
    })

    # Handle closing the old channel, if any
    case old_canonical_alias do
      # this is a new room, nothing to do
      nil ->
        nil

      old_canonical_alias ->
        # this is a known room that got renamed; part the old channel.
        send.(%Matrix2051.Irc.Command{
          tags: %{"account" => nick},
          source: nick,
          command: "PART",
          params: [
            new_canonical_alias,
            "This room was renamed to " <> new_canonical_alias
          ]
        })

        # And announce the change in the new one.
        send.(%Matrix2051.Irc.Command{
          source: "server",
          command: "NOTICE",
          params: [
            new_canonical_alias,
            "This room was renamed from " <> old_canonical_alias
          ]
        })
    end
  end

  defp handle_state_event(sup_mod, sup_pid, room_id, event) do
    state = sup_mod.matrix_state(sup_pid)
    writer = sup_mod.writer(sup_pid)

    channel =
      case Matrix2051.MatrixClient.State.room_canonical_alias(state, room_id) do
        nil -> room_id
        canonical_alias -> canonical_alias
      end

    Matrix2051.IrcConn.Writer.write_command(writer, %Matrix2051.Irc.Command{
      source: "server",
      command: "NOTICE",
      params: [
        channel,
        "Unknown state event (" <> event["type"] <> "): " <> Kernel.inspect(event)
      ]
    })
  end

  defp handle_timeline_event(sup_mod, sup_pid, room_id, event) do
    state = sup_mod.matrix_state(sup_pid)
    writer = sup_mod.writer(sup_pid)

    channel =
      case Matrix2051.MatrixClient.State.room_canonical_alias(state, room_id) do
        nil -> room_id
        canonical_alias -> canonical_alias
      end

    Matrix2051.IrcConn.Writer.write_command(writer, %Matrix2051.Irc.Command{
      source: "server",
      command: "NOTICE",
      params: [
        channel,
        "Unknown timeline event (" <> event["type"] <> "): " <> Kernel.inspect(event)
      ]
    })
  end

  defp handle_left_room(sup_mod, sup_pid, room_id, event) do
    state = sup_mod.matrix_state(sup_pid)
    writer = sup_mod.writer(sup_pid)
  end
end
