defmodule Matrix2051.Matrix.RawClient do
  @moduledoc """
    Sends queries to a Matrix homeserver.
  """
  defstruct [:base_url, :httpoison]

  @callback
  def get(client, path) do
    case client.httpoison.get!(client.base_url) do
      %HTTPoison.Response{status_code: 200, body: body} ->
        {:ok, Jason.decode!(body)}
    end
  end
end
