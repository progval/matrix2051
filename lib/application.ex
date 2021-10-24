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

defmodule Matrix2051.Application do
  @moduledoc """
    Main module of Matrix2051.
  """
  use Application

  @doc """
    Entrypoint. Takes the global config as args, and starts Matrix2051.Supervisor
  """
  @impl true
  def start(_type, args) do
    HTTPoison.start()

    children = [
      {Matrix2051.Supervisor, args}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
