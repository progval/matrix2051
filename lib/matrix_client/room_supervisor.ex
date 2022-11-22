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

defmodule M51.MatrixClient.RoomSupervisor do
  @moduledoc """
    Supervises a GenServer for each joined room, which receives events for
    the room and sends them to IRC.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    {sup_pid} = init_arg
    room_sup = M51.IrcConn.Supervisor.matrix_room_supervisor(sup_pid)
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: room_sup)
  end

  @impl true
  def init(init_arg) do
    {sup_pid} = init_arg

    ret = DynamicSupervisor.init(strategy: :one_for_one)

    Registry.register(M51.Registry, {sup_pid, :matrix_room_supervisor}, nil)

    ret
  end

  def start_or_get_room_handler(sup_pid, room_id) do
    room_sup = M51.IrcConn.Supervisor.matrix_room_supervisor(sup_pid)

    case Registry.lookup(M51.Registry, {sup_pid, :matrix_room_handler, room_id}) do
      [] ->
        {:ok, new_pid} =
          DynamicSupervisor.start_child(
            room_sup,
            {M51.MatrixClient.RoomHandler, {sup_pid, room_id}}
          )

        new_pid

      [{existing_pid, _}] ->
        existing_pid
    end
  end

  def handle_events(sup_pid, room_id, type, is_backlog, handled_event_ids, write, events) do
    # TODO: fetch handled_event_ids in the server instead of message-passing it
    # TODO: define write/1 in the server instead of message-passing it

    room_handler_pid = M51.MatrixClient.RoomSupervisor.start_or_get_room_handler(sup_pid, room_id)

    GenServer.cast(
      room_handler_pid,
      {:events, type, is_backlog, handled_event_ids, write, events}
    )
  end
end
