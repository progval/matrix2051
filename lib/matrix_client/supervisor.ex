defmodule Matrix2051.MatrixClient.Supervisor do
  @moduledoc """
    Supervises a Matrix client.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {} = args

    children = [
      {Matrix2051.MatrixClient.State, {__MODULE__, self()}},
      {Matrix2051.MatrixClient.Client, {__MODULE__, self()}},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.State child."
  def state(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.MatrixClient.State, 0)
    pid
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.Client child."
  def client(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.MatrixClient.Client, 0)
    pid
  end
end
