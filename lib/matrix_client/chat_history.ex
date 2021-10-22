##
# Copyright (C) 2021  Valentin Lorentz
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

defmodule Matrix2051.MatrixClient.ChatHistory do
  @moduledoc """
    Queries history when queried from IRC clients
  """

  def after_(sup_pid, room_id, event_id, limit) do
    client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)

    case Matrix2051.MatrixClient.Client.get_event_context(client, room_id, event_id, limit * 2) do
      {:ok, events} -> {:ok, process_events(sup_pid, room_id, events["events_after"])}
      {:error, message} -> {:error, message}
    end
  end

  def around(sup_pid, room_id, event_id, limit) do
    client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)

    case Matrix2051.MatrixClient.Client.get_event_context(client, room_id, event_id, limit) do
      {:ok, events} ->
        # TODO: if there aren't enough events after (resp. before), allow more
        # events before (resp. after) than half the limit.
        nb_before = ((limit - 1) / 2) |> Float.ceil() |> Kernel.trunc()
        nb_after = ((limit - 1) / 2) |> Kernel.trunc()

        events_before = events["events_before"] |> Enum.slice(0, nb_before) |> Enum.reverse()
        events_after = events["events_after"] |> Enum.slice(0, nb_after)
        events = Enum.concat([events_before, [events["event"]], events_after])

        {:ok, process_events(sup_pid, room_id, events)}

      {:error, message} ->
        {:error, message}
    end
  end

  def before(sup_pid, room_id, event_id, limit) do
    client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)

    case Matrix2051.MatrixClient.Client.get_event_context(client, room_id, event_id, limit * 2) do
      {:ok, events} ->
        {:ok, process_events(sup_pid, room_id, Enum.reverse(events["events_before"]))}

      {:error, message} ->
        {:error, message}
    end
  end

  defp process_events(sup_pid, room_id, events) do
    pid = self()
    write = fn cmd -> send(pid, {:command, cmd}) end

    # Run the poller with this "mock" write function.
    # This allows us to collect commands, so put them all in the chathistory batch.
    #
    # It is tempting to make Matrix2051.MatrixClient.Poller.handle_event return
    # a list of commands instead of making it send them directly, but it makes
    # it hard to deal with state changes.
    # TODO: still... it would be nice to find a way to avoid this.
    Task.async(fn ->
      Enum.map(events, fn event ->
        # TODO: dedup this computation with Poller
        sender =
          case Map.get(event, "sender") do
            nil -> nil
            sender -> String.replace_prefix(sender, "@", "")
          end

        Matrix2051.MatrixClient.Poller.handle_event(
          sup_pid,
          room_id,
          sender,
          false,
          write,
          event
        )
      end)

      send(pid, {:finished_processing})
    end)
    |> Task.await()

    # Collect all commands
    Stream.unfold(nil, fn _ ->
      receive do
        {:command, cmd} -> {cmd, nil}
        {:finished_processing} -> nil
      end
    end)
    |> Enum.to_list()
  end
end
