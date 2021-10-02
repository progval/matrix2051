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
      # Completely arbitrary value. Just make sure it's lower than recv_timeout
      # in RawClient
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
    new_rooms =
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

        handle_event(sup_mod, sup_pid, room_id, sender, true, event)
      end)

    # Send self JOIN, RPL_TOPIC/RPL_NOTOPIC, RPL_NAMREPLY
    new_rooms
    |> Enum.filter(fn room -> room != nil end)
    # dedup
    |> Map.new()
    |> Map.to_list()
    |> Enum.map(fn {room_id, {canonical_alias_sender, old_canonical_alias}} ->
      send_channel_welcome(
        sup_mod,
        sup_pid,
        room_id,
        canonical_alias_sender,
        old_canonical_alias,
        nil
      )
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

      handle_event(sup_mod, sup_pid, room_id, sender, false, event)
    end)
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         state_event,
         %{"type" => "m.room.canonical_alias"} = event
       ) do
    new_canonical_alias = event["content"]["alias"]
    state = sup_mod.matrix_state(sup_pid)

    old_canonical_alias =
      Matrix2051.MatrixClient.State.set_room_canonical_alias(
        state,
        room_id,
        new_canonical_alias
      )

    if !state_event do
      send_channel_welcome(sup_mod, sup_pid, room_id, sender, old_canonical_alias, event)
    end

    {room_id, {sender, old_canonical_alias}}
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         state_event,
         %{"type" => "m.room.join_rules"} = event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)
    send = make_send_function(sup_mod, sup_pid, event)

    if !state_event do
      mode =
        case event["content"]["join_rule"] do
          "public" -> "-i"
          "knock" -> "+i"
          "invite" -> "+i"
          "private" -> "+i"
        end

      send.(%Matrix2051.Irc.Command{
        tags: %{"account" => sender},
        source: sender,
        command: "MODE",
        params: [channel, mode]
      })
    end

    nil
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         state_event,
         %{"type" => "m.room.member"} = event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid, event)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    was_already_member = Matrix2051.MatrixClient.State.room_member_add(state, room_id, sender)

    if !state_event && !was_already_member do
      send.(%Matrix2051.Irc.Command{
        tags: %{"account" => sender},
        source: sender,
        command: "JOIN",
        params: [channel, sender, sender]
      })
    end

    nil
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         _state_event,
         %{"type" => "m.room.message"} = event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid, event)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    send.(%Matrix2051.Irc.Command{
      tags: %{"account" => sender},
      source: sender,
      command: "PRIVMSG",
      params: [channel, event["content"]["body"]]
    })

    nil
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         state_event,
         %{"type" => "m.room.name"} = event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid, event)

    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)
    Matrix2051.MatrixClient.State.set_room_name(state, room_id, event["content"]["name"])

    if !state_event do
      topic =
        case compute_topic(sup_mod, sup_pid, room_id) do
          nil -> ""
          {topic, _whotime} -> topic
        end

      send.(%Matrix2051.Irc.Command{source: sender, command: "TOPIC", params: [channel, topic]})
    end

    nil
  end

  defp handle_event(
         sup_mod,
         sup_pid,
         room_id,
         sender,
         state_event,
         %{"type" => "m.room.topic"} = event
       ) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid, event)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    Matrix2051.MatrixClient.State.set_room_topic(
      state,
      room_id,
      {event["content"]["topic"], sender, event["origin_server_ts"]}
    )

    if !state_event do
      topic =
        case compute_topic(sup_mod, sup_pid, room_id) do
          nil -> ""
          {topic, _whotime} -> topic
        end

      send.(%Matrix2051.Irc.Command{source: sender, command: "TOPIC", params: [channel, topic]})
    end

    nil
  end

  defp handle_event(sup_mod, sup_pid, room_id, _sender, _state_event, event) do
    state = sup_mod.matrix_state(sup_pid)
    send = make_send_function(sup_mod, sup_pid, event)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    case event["type"] do
      "m.room.create" ->
        nil

      "m.room.history_visibility" ->
        nil

      event_type ->
        send.(%Matrix2051.Irc.Command{
          source: "server",
          command: "NOTICE",
          params: [
            channel,
            "Unknown state event (" <> event_type <> "): " <> Kernel.inspect(event)
          ]
        })
    end

    nil
  end

  defp handle_left_room(sup_mod, sup_pid, _room_id, _event) do
    _state = sup_mod.matrix_state(sup_pid)
    _writer = sup_mod.writer(sup_pid)
    # TODO
  end

  defp compute_topic(sup_mod, sup_pid, room_id) do
    state = sup_mod.matrix_state(sup_pid)
    name = Matrix2051.MatrixClient.State.room_name(state, room_id)
    topicwhotime = Matrix2051.MatrixClient.State.room_topic(state, room_id)

    case {name, topicwhotime} do
      {nil, nil} -> nil
      {name, nil} -> {"[" <> name <> "]", nil}
      {nil, {topic, who, time}} -> {"[] " <> topic, {who, time}}
      {name, {topic, who, time}} -> {"[" <> name <> "] " <> topic, {who, time}}
    end
  end

  # Sends self JOIN, RPL_TOPIC/RPL_NOTOPIC, RPL_NAMREPLY
  defp send_channel_welcome(
         sup_mod,
         sup_pid,
         room_id,
         canonical_alias_sender,
         old_canonical_alias,
         event
       ) do
    irc_state = sup_mod.state(sup_pid)
    state = sup_mod.matrix_state(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(irc_state)
    channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    send = make_send_function(sup_mod, sup_pid, event)

    # Join the new channel
    send.(%Matrix2051.Irc.Command{
      tags: %{"account" => nick},
      source: nick,
      command: "JOIN",
      params: [channel, nick, nick]
    })

    # RPL_NAMREPLY
    Matrix2051.MatrixClient.State.room_members(state, room_id)
    |> Enum.map(fn member ->
      # TODO: group them in lines

      # RPL_NAMREPLY
      send.(%Matrix2051.Irc.Command{
        command: "353",
        params: [nick, "=", channel, member]
      })
    end)

    case compute_topic(sup_mod, sup_pid, room_id) do
      nil ->
        # RPL_NOTOPIC
        send.(%Matrix2051.Irc.Command{command: "331", params: [nick, channel]})

      {topic, whotime} ->
        # RPL_TOPIC
        send.(%Matrix2051.Irc.Command{
          command: "332",
          params: [nick, channel, topic]
        })

        case whotime do
          nil ->
            nil

          {who, time} ->
            # RPL_TOPICWHOTIME
            send.(%Matrix2051.Irc.Command{
              command: "333",
              params: [nick, channel, who, Integer.to_string(time)]
            })
        end
    end

    if old_canonical_alias != nil do
      announce_channel_rename(
        sup_mod,
        sup_pid,
        room_id,
        canonical_alias_sender,
        old_canonical_alias
      )
    end
  end

  defp announce_channel_rename(
         sup_mod,
         sup_pid,
         room_id,
         canonical_alias_sender,
         old_canonical_alias
       ) do
    irc_state = sup_mod.state(sup_pid)
    state = sup_mod.matrix_state(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(irc_state)
    new_canonical_alias = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

    send = make_send_function(sup_mod, sup_pid, nil)

    # this is a known room that got renamed; part the old channel.
    send.(%Matrix2051.Irc.Command{
      tags: %{"account" => nick},
      source: nick,
      command: "PART",
      params: [
        old_canonical_alias,
        canonical_alias_sender <> " renamed this room to " <> new_canonical_alias
      ]
    })

    # Announce the rename in the new room
    send.(%Matrix2051.Irc.Command{
      source: "server",
      command: "NOTICE",
      params: [
        new_canonical_alias,
        canonical_alias_sender <> " renamed this room from " <> old_canonical_alias
      ]
    })
  end

  # Returns a function that can be used to send messages
  defp make_send_function(sup_mod, sup_pid, event) do
    writer = sup_mod.writer(sup_pid)
    state = sup_mod.state(sup_pid)
    capabilities = Matrix2051.IrcConn.State.capabilities(state)

    fn cmd ->
      cmd =
        case event do
          nil ->
            cmd

          %{"origin_server_ts" => origin_server_ts, "event_id" => event_id} ->
            server_time = origin_server_ts |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
            %{cmd | tags: Map.merge(cmd.tags, %{"server_time" => server_time, "msgid" => event_id})}
        end

      Matrix2051.IrcConn.Writer.write_command(
        writer,
        Matrix2051.Irc.Command.downgrade(cmd, capabilities)
      )
    end
  end
end
