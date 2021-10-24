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

defmodule M51.MatrixClient.Supervisor do
  @moduledoc """
    Supervises a Matrix client.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {} = args

    children = [
      {M51.MatrixClient.State, {__MODULE__, self()}},
      {M51.MatrixClient.Client, {__MODULE__, self()}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Returns the pid of the M51.MatrixClient.State child."
  def state(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), M51.MatrixClient.State, 0)

    pid
  end

  @doc "Returns the pid of the M51.MatrixClient.Client child."
  def client(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), M51.MatrixClient.Client, 0)

    pid
  end
end
