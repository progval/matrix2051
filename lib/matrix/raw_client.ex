defmodule Matrix2051.Matrix.RawClient do
  @moduledoc """
    Sends queries to a Matrix homeserver.
  """
  defstruct [:base_url, :access_token, :httpoison]

  def get(client, path, headers \\ [], options \\ []) do
    headers = [Authorization: "Bearer " <> client.access_token] ++ headers
    # Need to be larger than Poller's timeout (time 1000 because this ones seems
    # to be in milliseconds)
    options = [recv_timeout: 1_000_000] ++ options

    case client.httpoison.get!(client.base_url <> path, headers, options) do
      %HTTPoison.Response{status_code: 200, body: body} ->
        {:ok, Jason.decode!(body)}

      %HTTPoison.Response{status_code: status_code, body: body} ->
        {:error, status_code, Jason.decode!(body)}
    end
  end

  def post(client, path, body, headers \\ [], options \\ []) do
    headers = [Authorization: "Bearer " <> client.access_token] ++ headers
    options = [recv_timeout: 1_000_000] ++ options

    case client.httpoison.post!(client.base_url <> path, body, headers, options) do
      %HTTPoison.Response{status_code: 200, body: body} ->
        {:ok, Jason.decode!(body)}

      %HTTPoison.Response{status_code: status_code, body: body} ->
        {:error, status_code, Jason.decode!(body)}
    end
  end
end
