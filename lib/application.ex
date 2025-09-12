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

defmodule M51.Application do
  @moduledoc """
    Main module of M51.
  """
  use Application

  require Logger

  @doc """
    Entrypoint. Takes the global config as args, and starts M51.Supervisor
  """
  @impl true
  def start(_type, args) do
    if Enum.member?(System.argv(), "--debug") do
      Logger.warning("Starting in debug mode")
      Logger.configure(level: :debug)
    else
      Logger.configure(level: :info)
    end

    HTTPoison.start()

    children = [
      {M51.Supervisor, args}
    ]

    {:ok, res} = Supervisor.start_link(children, strategy: :one_for_one)
    Logger.info("Matrix2051 started.")
    {:ok, res}
  end
end
