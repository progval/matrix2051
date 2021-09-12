defmodule Matrix2051.IrcConn.Reader do
  @moduledoc """
    Reads from a client, and dispatches lines.
  """

  use Task, restart: :permanent

  def start_link(args) do
    Task.start_link(__MODULE__, :serve, [args])
  end

  def serve(args) do
    {supervisor, sock} = args
    loop_serve(supervisor, sock)
  end

  defp loop_serve(supervisor, sock) do
    {:ok, line} = :gen_tcp.recv(sock, 0)
    {:ok, command} = Matrix2051.Irc.Command.parse(line)
    writer = Matrix2051.IrcConn.Supervisor.writer(supervisor)
    Matrix2051.IrcConn.Writer.write_line(writer, Matrix2051.Irc.Command.format(command))
    loop_serve(supervisor, sock)
  end
end
