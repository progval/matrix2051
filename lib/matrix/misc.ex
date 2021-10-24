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

defmodule M51.Matrix.Misc do
  def parse_userid(userid) do
    case String.split(userid, ":") do
      [local_name, hostname] ->
        if Regex.match?(~r|^[0-9a-z.=_/-]+$|, local_name) do
          if Regex.match?(~r/.*\s.*/u, hostname) do
            {:error, "\"" <> hostname <> "\" is not a valid hostname"}
          else
            {:ok, {local_name, hostname}}
          end
        else
          {:error,
           "your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/"}
        end

      [nick] ->
        {:error,
         "must contain a colon (':'), to separate the username and hostname. For example: " <>
           nick <> ":matrix.org"}

      _ ->
        {:error, "must not contain more than one colon."}
    end
  end
end
