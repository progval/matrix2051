##
# Copyright (C) 2021-2022  Valentin Lorentz
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
        cond do
          !Regex.match?(~r|^[0-9a-z.=_/-]+$|, local_name) ->
            {:error,
             "your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/"}

          Regex.match?(~r/.*\s.*/u, hostname) ->
            {:error, "\"#{hostname}\" is not a valid hostname"}

          true ->
            {:ok, {local_name, hostname}}
        end

      [local_name, hostname, port_str] ->
        port =
          case Integer.parse(port_str) do
            {i, ""} -> i
            _ -> nil
          end

        cond do
          !Regex.match?(~r|^[0-9a-z.=_/-]+$|, local_name) ->
            {:error,
             "your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/"}

          Regex.match?(~r/.*\s.*/u, hostname) ->
            {:error, "\"#{hostname}\" is not a valid hostname"}

          port == nil ->
            {:error, "\"#{port_str}\" is not a valid port number"}

          true ->
            {:ok, {local_name, "#{hostname}:#{port}"}}
        end

      [nick] ->
        {:error,
         "must contain a colon (':'), to separate the username and hostname. For example: " <>
           nick <> ":matrix.org"}

      _ ->
        {:error, "must not contain more than two colons."}
    end
  end
end
