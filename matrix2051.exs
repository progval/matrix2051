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

require Logger

if Enum.member?(System.argv(), "--debug") do
  Logger.warn("Starting in debug mode")
  Logger.configure(level: :debug)
else
  Logger.configure(level: :info)
end
{:ok, _} = M51.Application.start(:normal, [])
Logger.info("Matrix2051 started.")
