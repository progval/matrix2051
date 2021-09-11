defmodule Matrix2051.IrcConnState do
  @moduledoc """
    Stores the state of an open IRC connection.
  """
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {supervisor} = args
    {:ok, {supervisor}}
  end

end

