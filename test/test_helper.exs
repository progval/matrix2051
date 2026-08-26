##
# Copyright (C) 2021-2022  Valentin Lorentz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License version 3,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
###

ExUnit.start()
ExUnit.start(timeout: 5000)

Mox.defmock(MockHTTPoison, for: HTTPoison.Base)
M51.Config.set_httpoison(MockHTTPoison)

# Replaces the value defined in mix.exs, so tests don't depend on a particular
# value (which may be inconvenient for forks)
Application.put_env(:matrix2051, :source_code_url, "http://example.org/source.git")

Logger.configure(level: :info)

defmodule MockIrcConnWriter do
  use GenServer

  def start_link(args) do
    {test_pid} = args
    name = {:via, Registry, {M51.Registry, {test_pid, :irc_writer}}}
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(arg, _from, state) do
    {test_pid} = state
    send(test_pid, arg)
    {:reply, :ok, state}
  end
end

defmodule MockMatrixState do
  use Agent

  def start_link(args) do
    {test_pid} = args

    name = {:via, Registry, {M51.Registry, {test_pid, :matrix_state}}}

    Agent.start_link(
      fn ->
        %M51.MatrixClient.State{
          rooms: %{
            "!room_id:example.org" => %M51.Matrix.RoomState{
              synced: true,
              canonical_alias: "#existing_room:example.org",
              members: %{
                "user1:example.org" => %M51.Matrix.RoomMember{display_name: "user one"},
                "user2:example.com" => %M51.Matrix.RoomMember{}
              }
            }
          }
        }
      end,
      name: name
    )
  end
end

defmodule MockMatrixClient do
  use GenServer

  def start_link(args) do
    {sup_pid} = args
    name = {:via, Registry, {M51.Registry, {sup_pid, :matrix_client}}}
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init({sup_pid}) do
    {:ok,
     %M51.MatrixClient.Client{
       state: :initial_state,
       irc_pid: sup_pid,
       args: []
     }}
  end

  @impl true
  def handle_call({:connect, local_name, hostname, password, nil}, _from, state) do
    case {hostname, password} do
      {"i-hate-passwords.example.org", _} ->
        {:reply, {:error, :no_password_flow, "No password flow"}, state}

      {_, "correct password"} ->
        state = %{state | local_name: local_name, hostname: hostname}
        {:reply, {:ok}, %{state | state: :connected}}

      {_, "invalid password"} ->
        {:reply, {:error, :invalid_password, "Invalid password"}, state}
    end
  end

  @impl true
  def handle_call({:register, local_name, hostname, password}, _from, state) do
    case {local_name, password} do
      {"user", "my p4ssw0rd"} ->
        state = %{state | state: :connected, local_name: local_name, hostname: hostname}
        {:reply, {:ok, local_name <> ":" <> hostname}, state}

      {"reserveduser", _} ->
        {:reply, {:error, :exclusive, "This username is reserved"}, state}
    end
  end

  @impl true
  def handle_call({:join_room, room_alias}, _from, state) do
    case room_alias do
      "#existing_room:example.org" -> {:reply, {:ok, "!existing_room_id:example.org"}, state}
    end
  end

  @impl true
  def handle_call({:dump_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:get_event_context, _channel, _event_id, limit}, _from, state) do
    event1 = %{
      "content" => %{"body" => "first message", "msgtype" => "m.text"},
      "event_id" => "$event1",
      "origin_server_ts" => 1_632_946_233_579,
      "sender" => "@nick:example.org",
      "type" => "m.room.message",
      "unsigned" => %{}
    }

    event2 = %{
      "content" => %{"body" => "second message", "msgtype" => "m.text"},
      "event_id" => "$event2",
      "origin_server_ts" => 1_632_946_233_579,
      "sender" => "@nick:example.org",
      "type" => "m.room.message",
      "unsigned" => %{}
    }

    event3 = %{
      "content" => %{"body" => "third message", "msgtype" => "m.text"},
      "event_id" => "$event3",
      "origin_server_ts" => 1_632_946_233_579,
      "sender" => "@nick:example.org",
      "type" => "m.room.message",
      "unsigned" => %{}
    }

    event4 = %{
      "content" => %{"body" => "fourth message", "msgtype" => "m.text"},
      "event_id" => "$event4",
      "origin_server_ts" => 1_632_946_233_579,
      "sender" => "@nick:example.org",
      "type" => "m.room.message",
      "unsigned" => %{}
    }

    event5 = %{
      "content" => %{"body" => "fifth message", "msgtype" => "m.text"},
      "event_id" => "$event5",
      "origin_server_ts" => 1_632_946_233_579,
      "sender" => "@nick:example.org",
      "type" => "m.room.message",
      "unsigned" => %{}
    }

    reply =
      case limit do
        0 ->
          %{
            "start" => "start0",
            "end" => "end0",
            "events_before" => [],
            "event" => event3,
            "events_after" => []
          }

        1 ->
          %{
            "start" => "start1",
            "end" => "end1",
            "events_before" => [event2],
            "event" => event3,
            "events_after" => []
          }

        2 ->
          %{
            "start" => "start2",
            "end" => "end2",
            "events_before" => [event2],
            "event" => event3,
            "events_after" => [event4]
          }

        3 ->
          %{
            # reverse-chronological order, as per the spec
            "start" => "start3",
            "events_before" => [event2, event1],
            "event" => event3,
            "events_after" => [event4]
          }

        n when n >= 4 ->
          %{
            # reverse-chronological order, as per the spec
            "events_before" => [event2, event1],
            "event" => event3,
            "events_after" => [event4, event5]
          }
      end

    {:reply, {:ok, reply}, state}
  end

  @impl true
  def handle_call({:get_events_from_cursor, _channel, direction, cursor, _limit}, _from, state) do
    event = %{
      "content" => %{
        "body" => "event in direction #{direction} from #{cursor}",
        "msgtype" => "m.text"
      },
      "event_id" => "$event",
      "origin_server_ts" => 1_632_946_233_579,
      "sender" => "@nick:example.org",
      "type" => "m.room.message",
      "unsigned" => %{}
    }
    events = %{"state" => [], "chunk" => [event], "start" => "startcursor", "end" => "endcursor"}
    {:reply, {:ok, events}, state}
  end

  @impl true
  def handle_call({:get_latest_events, _channel, limit}, _from, state) do
    events =
      [
        %{
          "content" => %{"body" => "first message", "msgtype" => "m.text"},
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{"body" => "second message", "msgtype" => "m.text"},
          "event_id" => "$event2",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{"body" => "third message", "msgtype" => "m.text"},
          "event_id" => "$event3",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{"body" => "fourth message", "msgtype" => "m.text"},
          "event_id" => "$event4",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{"body" => "fifth message", "msgtype" => "m.text"},
          "event_id" => "$event5",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        }
      ]
      # Keep the last ones
      |> Enum.slice(-limit..-1)
      # "For dir=b events will be in reverse-chronological order"
      |> Enum.reverse()

    {:reply,
     {:ok, %{"state" => [], "chunk" => events, "from" => "fromcursor", "to" => "tocursor"}},
     state}
  end

  :w

  @impl true
  def handle_call({:is_valid_alias, _room_id, "#invalidalias:example.org"}, _from, state) do
    {:reply, false, state}
  end

  @impl true
  def handle_call({:is_valid_alias, _room_id, _room_alias}, _from, state) do
    {:reply, true, state}
  end

  @impl true
  def handle_call(msg, _from, state) do
    %M51.MatrixClient.Client{irc_pid: irc_pid} = state
    send(irc_pid, msg)
    {:reply, {:ok, nil}, state}
  end
end
