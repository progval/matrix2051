defmodule Matrix2051.IrcConn.Writer do
  @moduledoc """
    Writes lines to a client.
  """

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  def write_command(writer, command) do
    write_line(writer, Matrix2051.Irc.Command.format(command))
  end

  def write_line(writer, line) do
    GenServer.call(writer, {:write_line, line})
  end

  @impl true
  def handle_call(arg, _from, state) do
    {:write_line, line} = arg
    {_supervisor, sock} = state
    :gen_tcp.send(sock, line)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(arg, state) do
    IO.inspect("handle_cast")
    {:no_reply, state}
  end
end
