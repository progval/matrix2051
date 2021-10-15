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
      {Matrix2051.IrcConn.State, {self()}},
      {Matrix2051.IrcConn.Writer, {self(), sock}},
      {Matrix2051.MatrixClient.State, {self()}},
      {Matrix2051.MatrixClient.Client, {self(), []}},
      {Matrix2051.MatrixClient.Sender, {self()}},
      {Matrix2051.MatrixClient.Poller, {self()}},
      {Matrix2051.IrcConn.Handler, {self()}},
      {Matrix2051.IrcConn.Reader, {self(), sock}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.State child."
  def state(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :irc_state}}}
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.Writer child."
  def writer(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :irc_writer}}}
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.Client child."
  def matrix_client(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :matrix_client}}}
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.Sender child."
  def matrix_sender(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :matrix_sender}}}
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.State child."
  def matrix_state(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :matrix_state}}}
  end

  @doc "Returns the pid of the Matrix2051.MatrixClient.Poller child."
  def matrix_poller(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :matrix_poller}}}
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.Handler child."
  def handler(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :irc_handler}}}
  end

  @doc "Returns the pid of the Matrix2051.IrcConn.Reader child."
  def reader(sup) do
    {:via, Registry, {Matrix2051.Registry, {sup, :irc_reader}}}
  end
end
