defmodule Matrix2051.Supervisor do
  @moduledoc """
    Main supervisor of Matrix2051. Starts the Matrix2051.Config agent,
    and the Matrix2051.MatrixClient and Matrix2051.IrcServer trees.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    children = [
      {Matrix2051.Config, args},
      Matrix2051.MatrixClientPool,
      Matrix2051.IrcServer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
