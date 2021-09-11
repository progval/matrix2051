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
    writer = Matrix2051.IrcConn.Supervisor.writer(supervisor)
    Matrix2051.IrcConnWriter.write_line(writer, line)
    loop_serve(supervisor, sock)
  end
end
