defmodule Matrix2051.IrcConnSupervisor do
  @moduledoc """
    Supervises the connection with a single IRC client: Matrix2051.IrcConnState
    to store its state, and Matrix2051.IrcConnWriter and Matrix2051.IrcConnReader
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
      {Matrix2051.IrcConnState, {self()}},
      {Matrix2051.IrcConnWriter, {self(), sock}},
      {Matrix2051.IrcConnReader, {self(), sock}},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Returns the pid of the Matrix2051.IrcConnState child."
  def state(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConnState, 0)
    pid
  end

  @doc "Returns the pid of the Matrix2051.IrcConnReader child."
  def reader(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConnReader, 0)
    pid
  end

  @doc "Returns the pid of the Matrix2051.IrcConnWriter child."
  def writer(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConnWriter, 0)
    pid
  end
end
