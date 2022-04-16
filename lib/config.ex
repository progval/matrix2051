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

defmodule M51.Config do
  @moduledoc """
    Global configuration.
  """
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, fn -> args end, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, []}
  end

  @impl true
  def handle_call({:get_httpoison}, _from, state) do
    {:reply, Keyword.get(state, :httpoison, HTTPoison), state}
  end

  @impl true
  def handle_call({:set_httpoison, httpoison}, _from, state) do
    {:reply, {}, Keyword.put(state, :httpoison, httpoison)}
  end

  def httpoison() do
    GenServer.call(__MODULE__, {:get_httpoison})
  end

  def set_httpoison(httpoison) do
    GenServer.call(__MODULE__, {:set_httpoison, httpoison})
  end

  def port() do
    2051
  end
end
