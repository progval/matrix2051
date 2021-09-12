defmodule MockIrcConnWriter do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(arg, _from, state) do
    {:write_line, line} = arg
    {test_pid} = state
    send(test_pid, {:line, line})
    {:reply, :ok, state}
  end
end

defmodule MockIrcConnSupervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {parent} = args

    children = [
      {Matrix2051.IrcConn.State, {MockIrcConnSupervisor, self()}},
      {Matrix2051.IrcConn.Handler, {MockIrcConnSupervisor, self()}},
      {MockIrcConnWriter, {parent}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def state(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConn.State, 0)
    pid
  end

  def handler(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), Matrix2051.IrcConn.Handler, 0)
    pid
  end

  def writer(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), MockIrcConnWriter, 0)
    pid
  end
end

defmodule Matrix2051.IrcConn.HandlerTest do
  use ExUnit.Case
  doctest Matrix2051.IrcConn.Handler

  setup do
    start_supervised!({Matrix2051.Config, [matrix_id: "localname:homeserver.example.org"]})
    supervisor = start_supervised!({MockIrcConnSupervisor, {self()}})

    %{
      supervisor: supervisor,
      state: MockIrcConnSupervisor.state(supervisor),
      handler: MockIrcConnSupervisor.handler(supervisor)
    }
  end

  def cmd(line) do
    {:ok, command} = Matrix2051.Irc.Command.parse(line)
    command
  end

  def assert_welcome() do
    receive do
      msg -> assert msg == {:line, "001 * * :Welcome to this Matrix bouncer.\r\n"}
    end

    receive do
      msg ->
        assert msg == {:line, "005 * * CASEMAPPING=rfc3454 CHANLIMIT= :TARGMAX=JOIN:1,PART:1\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "375 * * :- Message of the day\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "372 * * :Welcome to Matrix2051, a Matrix bouncer.\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "376 * * :End of /MOTD command.\r\n"}
    end
  end

  test "non-IRCv3 registration", %{state: state, handler: handler} do
    send(handler, cmd("NICK foo"))

    send(handler, cmd("PING sync1"))

    receive do
      msg -> assert msg == {:line, "PONG :sync1\r\n"}
    end

    send(handler, cmd("USER ident * * :My GECOS"))
    assert_welcome()

    receive do
      msg -> assert msg == {:line, ":foo NICK :localname:homeserver.example.org\r\n"}
    end

    send(handler, cmd("PING sync2"))

    receive do
      msg -> assert msg == {:line, "PONG :sync2\r\n"}
    end

    assert Matrix2051.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "IRCv3 registration", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS"))

    receive do
      msg -> assert msg == {:line, "CAP * LS :\r\n"}
    end

    send(handler, cmd("PING sync1"))

    receive do
      msg -> assert msg == {:line, "PONG :sync1\r\n"}
    end

    send(handler, cmd("NICK foo"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("PING sync2"))

    receive do
      msg -> assert msg == {:line, "PONG :sync2\r\n"}
    end

    send(handler, cmd("CAP END"))
    assert_welcome()

    receive do
      msg -> assert msg == {:line, ":foo NICK :localname:homeserver.example.org\r\n"}
    end

    assert Matrix2051.IrcConn.State.gecos(state) == "My GECOS"
  end
end
