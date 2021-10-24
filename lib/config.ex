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
  use Agent

  def start_link(args) do
    Agent.start_link(fn -> args end, name: __MODULE__)
  end

  def httpoison() do
    Agent.get(__MODULE__, &Keyword.get(&1, :httpoison, HTTPoison))
  end

  def port() do
    2051
  end
end
