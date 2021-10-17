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

defmodule Matrix2051.MatrixClient.Sender do
  @moduledoc """
    Sends events to the homeserver.

    Reads messages and repeatedly tries to send them in order until they succeed.
  """
  use Task, restart: :permanent

  # totals 4 minutes, as the backoff of each attempt is 2^(number of attempts so far)
  @max_attempts 7

  def start_link(args) do
    Task.start_link(__MODULE__, :poll, [args])
  end

  def poll(args) do
    {sup_pid} = args
    Registry.register(Matrix2051.Registry, {sup_pid, :matrix_sender}, nil)
    loop_poll(sup_pid)
  end

  defp loop_poll(sup_pid) do
    receive do
      {:send, room_id, event_type, transaction_id, event} ->
        loop_send(sup_pid, room_id, event_type, transaction_id, event)
    end

    loop_poll(sup_pid)
  end

  defp loop_send(sup_pid, room_id, event_type, transaction_id, event, nb_attempts \\ 0) do
    client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)
    send = make_send_function(sup_pid, transaction_id)

    case Matrix2051.MatrixClient.Client.raw_client(client) do
      nil ->
        # Wait for it to be initialized
        Process.sleep(100)
        loop_send(sup_pid, room_id, event_type, transaction_id, event)

      raw_client ->
        path = "/_matrix/client/r0/rooms/#{room_id}/send/#{event_type}/#{transaction_id}"

        body = Jason.encode!(event)

        IO.inspect(body, label: "sending")

        case Matrix2051.Matrix.RawClient.put(raw_client, path, body) do
          {:ok, _body} ->
            nil

          {:error, _status_code, reason} ->
            if nb_attempts < @max_attempts do
              IO.inspect(reason, label: "error while sending event, retrying")
              backoff_delay = :math.pow(2, nb_attempts)
              Process.sleep(round(backoff_delay * 1000))

              loop_send(
                sup_pid,
                room_id,
                event_type,
                transaction_id,
                event,
                nb_attempts + 1
              )
            else
              IO.inspect(reason, label: "error while sending event, giving up")
              state = Matrix2051.IrcConn.Supervisor.matrix_state(sup_pid)
              channel = Matrix2051.MatrixClient.State.room_irc_channel(state, room_id)

              send.(%Matrix2051.Irc.Command{
                source: "server",
                command: "NOTICE",
                params: [channel, "Error while sending message: " <> Kernel.inspect(reason)]
              })
            end
        end
    end
  end

  # Returns a function that can be used to send messages
  defp make_send_function(sup_pid, transaction_id) do
    writer = Matrix2051.IrcConn.Supervisor.writer(sup_pid)
    state = Matrix2051.IrcConn.Supervisor.state(sup_pid)
    capabilities = Matrix2051.IrcConn.State.capabilities(state)
    label = Matrix2051.MatrixClient.Client.transaction_id_to_label(transaction_id)

    fn cmd ->
      cmd =
        case label do
          nil -> cmd
          _ -> %{cmd | tags: %{cmd.tags | "label" => label}}
        end

      Matrix2051.IrcConn.Writer.write_command(
        writer,
        Matrix2051.Irc.Command.downgrade(cmd, capabilities)
      )
    end
  end

  def queue_event(sup_pid, room_id, event_type, transaction_id, event) do
    Registry.send(
      {Matrix2051.Registry, {sup_pid, :matrix_sender}},
      {:send, room_id, event_type, transaction_id, event}
    )
  end
end
