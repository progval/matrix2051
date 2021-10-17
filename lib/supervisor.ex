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

defmodule Matrix2051.Supervisor do
  @moduledoc """
    Main supervisor of Matrix2051. Starts the Matrix2051.Config agent,
    and the Matrix2051.IrcServer tree.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    children = [
      {Registry, keys: :unique, name: Matrix2051.Registry},
      {Matrix2051.Config, args},
      Matrix2051.IrcServer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
