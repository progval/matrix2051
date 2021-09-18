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
    GenServer.call(writer, {:line, line})
  end

  def close(writer) do
    GenServer.call(writer, {:close})
  end

  @impl true
  def handle_call(arg, _from, state) do
    case arg do
      {:line, line} ->
        {_supervisor, sock} = state
        :gen_tcp.send(sock, line)

      {:close} ->
        {_supervisor, sock} = state
        :gen_tcp.close(sock)
    end

    {:reply, :ok, state}
  end
end
