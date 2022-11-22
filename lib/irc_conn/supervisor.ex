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

defmodule M51.IrcConn.Supervisor do
  @moduledoc """
    Supervises the connection with a single IRC client: M51.IrcConn.State
    to store its state, and M51.IrcConn.Writer and M51.IrcConn.Reader
    to interact with it.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {sock} = args

    children = [
      {M51.IrcConn.State, {self()}},
      {M51.IrcConn.Writer, {self(), sock}},
      {M51.MatrixClient.State, {self()}},
      {M51.MatrixClient.Client, {self(), []}},
      {M51.MatrixClient.Sender, {self()}},
      {M51.MatrixClient.Poller, {self()}},
      {M51.MatrixClient.RoomSupervisor, {self()}},
      {M51.IrcConn.Handler, {self()}},
      {M51.IrcConn.Reader, {self(), sock}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Returns the pid of the M51.IrcConn.State child."
  def state(sup) do
    {:via, Registry, {M51.Registry, {sup, :irc_state}}}
  end

  @doc "Returns the pid of the M51.IrcConn.Writer child."
  def writer(sup) do
    {:via, Registry, {M51.Registry, {sup, :irc_writer}}}
  end

  @doc "Returns the pid of the M51.MatrixClient.Client child."
  def matrix_client(sup) do
    {:via, Registry, {M51.Registry, {sup, :matrix_client}}}
  end

  @doc "Returns the pid of the M51.MatrixClient.Sender child."
  def matrix_sender(sup) do
    {:via, Registry, {M51.Registry, {sup, :matrix_sender}}}
  end

  @doc "Returns the pid of the M51.MatrixClient.State child."
  def matrix_state(sup) do
    {:via, Registry, {M51.Registry, {sup, :matrix_state}}}
  end

  @doc "Returns the pid of the M51.MatrixClient.Poller child."
  def matrix_poller(sup) do
    {:via, Registry, {M51.Registry, {sup, :matrix_poller}}}
  end

  @doc "Returns the pid of the M51.IrcConn.Handler child."
  def matrix_room_supervisor(sup) do
    {:via, Registry, {M51.Registry, {sup, :matrix_room_supervisor}}}
  end

  @doc "Returns the pid of the M51.IrcConn.Handler child."
  def handler(sup) do
    {:via, Registry, {M51.Registry, {sup, :irc_handler}}}
  end

  @doc "Returns the pid of the M51.IrcConn.Reader child."
  def reader(sup) do
    {:via, Registry, {M51.Registry, {sup, :irc_reader}}}
  end
end
