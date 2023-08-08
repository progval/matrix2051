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

defmodule M51.MatrixClient.Sender do
  @moduledoc """
    Sends events to the homeserver.

    Reads messages and repeatedly tries to send them in order until they succeed.
  """
  use Task, restart: :permanent

  require Logger

  # totals 4 minutes, as the backoff of each attempt is 2^(number of attempts so far)
  @max_attempts 7

  def start_link(args) do
    Task.start_link(__MODULE__, :poll, [args])
  end

  def poll(args) do
    {sup_pid} = args
    Registry.register(M51.Registry, {sup_pid, :matrix_sender}, nil)
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
    client = M51.IrcConn.Supervisor.matrix_client(sup_pid)
    send = make_send_function(sup_pid, transaction_id)

    case M51.MatrixClient.Client.raw_client(client) do
      nil ->
        # Wait for it to be initialized
        Process.sleep(100)
        loop_send(sup_pid, room_id, event_type, transaction_id, event)

      raw_client ->
        path =
          "/_matrix/client/r0/rooms/#{urlquote(room_id)}/send/#{urlquote(event_type)}/#{urlquote(transaction_id)}"

        body = Jason.encode!(event)

        Logger.debug("Sending event: #{body}")

        case M51.Matrix.RawClient.put(raw_client, path, body) do
          {:ok, _body} ->
            nil

          {:error, _status_code, reason} ->
            if nb_attempts < @max_attempts do
              Logger.warn("Error while sending event, retrying: #{Kernel.inspect(reason)}")
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
              Logger.warn("Error while sending event, giving up: #{Kernel.inspect(reason)}")
              state = M51.IrcConn.Supervisor.matrix_state(sup_pid)
              channel = M51.MatrixClient.State.room_irc_channel(state, room_id)

              send.(%M51.Irc.Command{
                source: "server.",
                command: "NOTICE",
                params: [channel, "Error while sending message: " <> Kernel.inspect(reason)]
              })
            end
        end
    end
  end

  # Returns a function that can be used to send messages
  defp make_send_function(sup_pid, transaction_id) do
    writer = M51.IrcConn.Supervisor.writer(sup_pid)
    state = M51.IrcConn.Supervisor.state(sup_pid)
    capabilities = M51.IrcConn.State.capabilities(state)
    label = M51.MatrixClient.Client.transaction_id_to_label(transaction_id)

    fn cmd ->
      cmd =
        case label do
          nil -> cmd
          _ -> %{cmd | tags: %{cmd.tags | "label" => label}}
        end

      M51.IrcConn.Writer.write_command(
        writer,
        M51.Irc.Command.downgrade(cmd, capabilities)
      )
    end
  end

  def queue_event(sup_pid, room_id, event_type, transaction_id, event) do
    Registry.send(
      {M51.Registry, {sup_pid, :matrix_sender}},
      {:send, room_id, event_type, transaction_id, event}
    )
  end

  defp urlquote(s) do
    M51.Matrix.Utils.urlquote(s)
  end
end
