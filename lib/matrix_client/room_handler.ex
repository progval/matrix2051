##
# Copyright (C) 2022  Valentin Lorentz
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

defmodule M51.MatrixClient.RoomHandler do
  @moduledoc """
    Receives events from a Matrix room and sends them to IRC.
  """

  use GenServer

  def start_link(args) do
    {sup_pid, room_id} = args

    GenServer.start_link(__MODULE__, args,
      name: {:via, Registry, {M51.Registry, {sup_pid, :matrix_room_handler, room_id}}}
    )
  end

  @impl true
  def init(args) do
    {sup_pid, room_id} = args

    {:ok, {sup_pid, room_id}}
  end

  @impl true
  def handle_cast({:events, :join, is_backlog, handled_event_ids, write, events}, state) do
    {sup_pid, room_id} = state

    M51.MatrixClient.Poller.handle_joined_room(
      sup_pid,
      is_backlog,
      handled_event_ids,
      room_id,
      write,
      events
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:events, :leave, is_backlog, handled_event_ids, write, events}, state) do
    {sup_pid, room_id} = state

    M51.MatrixClient.Poller.handle_left_room(
      sup_pid,
      is_backlog,
      handled_event_ids,
      room_id,
      write,
      events
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:events, :invite, is_backlog, handled_event_ids, write, events}, state) do
    {sup_pid, room_id} = state

    M51.MatrixClient.Poller.handle_invited_room(
      sup_pid,
      is_backlog,
      handled_event_ids,
      room_id,
      write,
      events
    )

    {:noreply, state}
  end
end
