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

  @doc """
    Internal method that dispatches event; public only so it can be unit-tested.
  """
  def handle_events(sup_mod, sup_pid, events) do
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
      sender =
        case Map.get(event, "sender") do
          nil -> nil
          sender -> String.replace_prefix(sender, "@", "")
        end

      handle_event(sup_mod, sup_pid, room_id, sender, event)
    end)

    room_event
    |> Map.get("timeline", %{})
    |> Map.get("events", [])
    # oldest first
    |> Enum.reverse()
    |> Enum.map(fn event ->
      sender =
        case Map.get(event, "sender") do
          nil -> nil
          sender -> String.replace_prefix(sender, "@", "")
        end

      handle_event(sup_mod, sup_pid, room_id, sender, event)
    end)
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         %{"type" => "m.room.canonical_alias"} = event
       ) do
    new_canonical_alias = event["content"]["alias"]
    irc_state = sup_mod.state(sup_pid)
    state = sup_mod.matrix_state(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(irc_state)

    send = make_send_function(sup_mod, sup_pid)

    old_canonical_alias =
      Matrix2051.MatrixClient.State.set_room_canonical_alias(
        state,
        room_id,
        new_canonical_alias
      )

    # old_canonical_alias is nil if this is a new room

    if old_canonical_alias != new_canonical_alias do
      # Join the new channel
      send.(%Matrix2051.Irc.Command{
        tags: %{"account" => nick},
        source: nick,
        command: "JOIN",
        params: [new_canonical_alias, nick, nick]
      })

      # Send joins for other users
      Matrix2051.MatrixClient.State.room_members(state, room_id)
      |> Enum.map(fn member ->
        if member != nick do
          send.(%Matrix2051.Irc.Command{
            tags: %{"account" => member},
            source: member,
            command: "JOIN",
            params: [new_canonical_alias, member, member]
          })
        end
      end)

      case compute_topic(sup_mod, sup_pid, room_id) do
        nil ->
          # RPL_NOTOPIC
          send.(%Matrix2051.Irc.Command{command: "331", params: [nick, new_canonical_alias]})

        topic ->
          # RPL_TOPIC
          send.(%Matrix2051.Irc.Command{
            command: "332",
            params: [nick, new_canonical_alias, topic]
          })
      end

      # Handle closing the old channel, if any
      case old_canonical_alias do
        # this is a new room, nothing to do
        nil ->
          nil

        old_canonical_alias when old_canonical_alias != new_canonical_alias ->
          # this is a known room that got renamed; part the old channel.
          send.(%Matrix2051.Irc.Command{
            tags: %{"account" => nick},
            source: nick,
            command: "PART",
            params: [
              old_canonical_alias,
              (sender || "someone") <> " renamed this room to " <> new_canonical_alias
            ]
          })

          # And announce the change in the new one.
          send.(%Matrix2051.Irc.Command{
            source: "server",
            command: "NOTICE",
            params: [
              new_canonical_alias,
              (sender || "someone") <>
                " renamed this room was renamed from " <> old_canonical_alias
            ]
          })
      end
    end
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         %{"type" => "m.room.member"} = _event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    if !Matrix2051.MatrixClient.State.room_member_add(state, room_id, sender) do
      send.(%Matrix2051.Irc.Command{
        tags: %{"account" => sender},
        source: sender,
        command: "JOIN",
        params: [channel, sender, sender]
      })
    end
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         %{"type" => "m.room.name"} = event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid)

    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)
    Matrix2051.MatrixClient.State.set_room_name(state, room_id, event["content"]["name"])

    topic =
      case compute_topic(sup_mod, sup_pid, room_id) do
        nil -> ""
        topic -> topic
      end

    send.(%Matrix2051.Irc.Command{source: sender, command: "TOPIC", params: [channel, topic]})
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         %{"type" => "m.room.topic"} = event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)
    Matrix2051.MatrixClient.State.set_room_topic(state, room_id, event["content"]["topic"])

    topic =
      case compute_topic(sup_mod, sup_pid, room_id) do
        nil -> ""
        topic -> topic
      end

    send.(%Matrix2051.Irc.Command{source: sender, command: "TOPIC", params: [channel, topic]})
  end

  defp handle_event(sup_mod, sup_pid, room_id, _sender, event) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    send.(%Matrix2051.Irc.Command{
      source: "server",
      command: "NOTICE",
      params: [
        channel,
        "Unknown state event (" <> event["type"] <> "): " <> Kernel.inspect(event)
      ]
    })
  end

  defp handle_left_room(sup_mod, sup_pid, _room_id, _event) do
    _state = sup_mod.matrix_state(sup_pid)
    _writer = sup_mod.writer(sup_pid)
    # TODO
  end

  defp compute_topic(sup_mod, sup_pid, room_id) do
    state = sup_mod.matrix_state(sup_pid)
    name = Matrix2051.MatrixClient.State.room_name(state, room_id)
    topic = Matrix2051.MatrixClient.State.room_topic(state, room_id)

    case {name, topic} do
      {nil, nil} -> nil
      {name, nil} -> "[" <> name <> "]"
      {nil, topic} -> "[] " <> topic
      {name, topic} -> "[" <> name <> "] " <> topic
    end
  end

  # Returns a function that can be used to send messages
  defp make_send_function(sup_mod, sup_pid) do
    writer = sup_mod.writer(sup_pid)
    state = sup_mod.state(sup_pid)
    capabilities = Matrix2051.IrcConn.State.capabilities(state)

    fn cmd ->
      Matrix2051.IrcConn.Writer.write_command(
        writer,
        Matrix2051.Irc.Command.downgrade(cmd, capabilities)
      )
    end
  end
end
