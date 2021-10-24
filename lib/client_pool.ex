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

defmodule M51.ClientPool do
  @moduledoc """
    Supervises matrix clients; one per user:homeserver.
  """

  use DynamicSupervisor

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    ret = DynamicSupervisor.init(strategy: :one_for_one)

    Task.start_link(fn ->
      DynamicSupervisor.start_child(
        __MODULE__,
        {Registry, name: M51.ClientRegistry}
      )
    end)

    ret
  end

  def start_or_get_client(matrix_id) do
    # TODO: there has to be a better way to atomically do this than create one and immediately
    # terminate it...
    {:ok, new_pid} =
      DynamicSupervisor.start_child(
        __MODULE__,
        {M51.Client, {matrix_id}}
      )

    case Registry.register({M51.ClientRegistry, keys: :duplicate}, matrix_id, new_pid) do
      {:ok, _} ->
        new_pid

      {:error, {:already_registered, existing_pid}} ->
        # There is already a client for that matrix_id. Terminate the client we just
        # created, then return the existing one
        :ok = DynamicSupervisor.terminate_child(M51.ClientSupervisor, new_pid)
        existing_pid
    end
  end
end
