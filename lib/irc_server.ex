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

defmodule M51.IrcServer do
  @moduledoc """
    Holds the main server socket and spawns a supervised
    M51.IrcConn.Supervisor process for each incoming IRC connection.
  """
  use Supervisor

  require Logger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    port = M51.Config.port()

    children = [
      {DynamicSupervisor, name: M51.IrcServer.DynamicSupervisor, strategy: :one_for_one},
      {Task, fn -> accept(port) end}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp accept(port, retries_left \\ 10) do
    opts = [
      :binary, :inet6,
      packet: :line,
      active: false,
      reuseaddr: true,
      buffer: M51.IrcConn.Handler.multiline_max_bytes * 2
    ]
    case :gen_tcp.listen(port, opts) do
      {:ok, server_sock} ->
        Logger.info("Listening on port #{port}")
        loop_accept(server_sock)

      {:error, :eaddrinuse} when retries_left > 0 ->
        # happens sometimes when recovering from a crash...
        Process.sleep(100)
        accept(port, retries_left - 1)
    end
  end

  defp loop_accept(server_sock) do
    {:ok, sock} = :gen_tcp.accept(server_sock)

    {:ok, {peer_address, peer_port}} = :inet.peername(sock)

    Logger.info("Incoming connection from #{:inet_parse.ntoa(peer_address)}:#{peer_port}")

    {:ok, conn_supervisor} =
      DynamicSupervisor.start_child(
        M51.IrcServer.DynamicSupervisor,
        {M51.IrcConn.Supervisor, {sock}}
      )

    :ok = :gen_tcp.controlling_process(sock, conn_supervisor)

    loop_accept(server_sock)
  end
end
