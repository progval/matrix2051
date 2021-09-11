defmodule Matrix2051.IrcServer do
  @moduledoc """
    Holds the main server socket and spawns a supervised
    Matrix2051.IrcConn.Supervisor process for each incoming IRC connection.
  """
  use DynamicSupervisor

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    port = Matrix2051.Config.port()
    ret = DynamicSupervisor.init(strategy: :one_for_one)

    Task.start_link(fn ->
      DynamicSupervisor.start_child(
        __MODULE__,
        {Task.Supervisor, name: Matrix2051.IrcServer.TaskSupervisor}
      )

      DynamicSupervisor.start_child(
        __MODULE__,
        {Task, fn -> accept(port) end}
      )
    end)

    ret
  end

  defp accept(port) do
    {:ok, server_sock} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    loop_accept(server_sock)
  end

  defp loop_accept(server_sock) do
    {:ok, sock} = :gen_tcp.accept(server_sock)

    {:ok, conn_supervisor} = DynamicSupervisor.start_child(
      __MODULE__,
      {Matrix2051.IrcConn.Supervisor, {sock}}
    )

    :ok = :gen_tcp.controlling_process(sock, Matrix2051.IrcConn.Supervisor.reader(conn_supervisor))

    loop_accept(server_sock)
  end
end
