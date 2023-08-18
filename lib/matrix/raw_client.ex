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

defmodule M51.Matrix.RawClient do
  require Logger

  @moduledoc """
    Sends queries to a Matrix homeserver.
  """
  defstruct [:base_url, :access_token, :httpoison]

  def get(client, path, headers \\ [], options \\ []) do
    headers = [Authorization: "Bearer " <> client.access_token] ++ headers
    options = options |> Keyword.put_new(:timeout, 60000)

    url = client.base_url <> path

    Logger.debug("GET #{url}")

    response = client.httpoison.get(url, headers, options)
    Logger.debug(Kernel.inspect(response))

    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, status_code, body}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, nil, reason}
    end
  end

  def post(client, path, body, headers \\ [], options \\ []) do
    headers = [Authorization: "Bearer " <> client.access_token] ++ headers
    options = options |> Keyword.put_new(:timeout, 60000)

    url = client.base_url <> path

    Logger.debug("POST #{url} " <> Kernel.inspect(body))

    response = client.httpoison.post(url, body, headers, options)

    Logger.debug(Kernel.inspect(response))

    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, status_code, Jason.decode!(body)}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, nil, reason}
    end
  end

  def put(client, path, body, headers \\ [], options \\ []) do
    headers = [Authorization: "Bearer " <> client.access_token] ++ headers
    options = options |> Keyword.put_new(:timeout, 60000)

    url = client.base_url <> path

    Logger.debug("POST #{url} " <> Kernel.inspect(body))

    response = client.httpoison.put(url, body, headers, options)
    Logger.debug(Kernel.inspect(response))

    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, status_code, Jason.decode!(body)}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, nil, reason}
    end
  end
end
