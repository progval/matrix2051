defmodule RawMatrixClient do
  @moduledoc """
    Sends queries to a Matrix homeserver.
  """
  defstruct [:base_url, :httpoison]

  @callback
  def get(client, path) do
    IO.inspect(client)
    IO.inspect(path)
  end
end
