defmodule Matrix2051.MatrixClient.State do
  @moduledoc """
    Stores the state of a Matrix client (access token, joined rooms, ...)
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end)
  end
end
