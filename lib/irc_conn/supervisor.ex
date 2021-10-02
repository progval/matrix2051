defmodule Matrix2051.IrcConn.Supervisor do
  @moduledoc """
    Supervises the connection with a single IRC client: Matrix2051.IrcConn.State
    to store its state, and Matrix2051.IrcConn.Writer and Matrix2051.IrcConn.Reader
    to interact with it.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {sock} = args

    children = [
      {Matrix2051.IrcConn.State, {__MODULE__, self()}},
      {Matrix2051.IrcConn.Writer, {self(), sock}},
      {Matrix2051.MatrixClient.State, {__MODULE__, self()}},
      {Matrix2051.MatrixClient.Client, {__MODULE__, self(), []}},
      {Matrix2051.MatrixClient.Poller, {__MODULE__, self()}},
      {Matrix2051.IrcConn.Handler, {__MODULE__, self()}},
      {Matrix2051.IrcConn.Reader, {self(), sock}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.State child."
  def state(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConn.State, 0)
    pid
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.Writer child."
  def writer(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConn.Writer, 0)
    pid
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.Client child."
  def matrix_client(sup) do
    {_, pid, _, _} =
      List.keyfind(Supervisor.which_children(sup), Matrix2051.MatrixClient.Client, 0)

    pid
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.State child."
  def matrix_state(sup) do
    {_, pid, _, _} =
      List.keyfind(Supervisor.which_children(sup), Matrix2051.MatrixClient.State, 0)

    pid
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.Poller child."
  def matrix_poller(sup) do
    {_, pid, _, _} =
      List.keyfind(Supervisor.which_children(sup), Matrix2051.MatrixClient.Poller, 0)

    pid
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.Handler child."
  def handler(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConn.Handler, 0)
    pid
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.Reader child."
  def reader(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConn.Reader, 0)
    pid
  end
end
