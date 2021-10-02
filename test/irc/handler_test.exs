defmodule MockMatrixClient do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init({_sup_mod, _sup_pid}) do
    {:ok,
     %Matrix2051.MatrixClient.Client{
       state: :initial_state,
       args: []
     }}
  end

  @impl true
  def handle_call({:connect, local_name, hostname, password}, _from, state) do
    case {hostname, password} do
      {"i-hate-passwords.example.org", _} ->
        {:reply, {:error, :no_password_flow, "No password flow"}, state}

      {_, "correct password"} ->
        state = [local_name: local_name, hostname: hostname] ++ state
        {:reply, {:ok}, {:connected, state}}

      {_, "invalid password"} ->
        {:reply, {:error, :invalid_password, "Invalid password"}, state}
    end
  end

  @impl true
  def handle_call({:register, local_name, hostname, password}, _from, state) do
    case {local_name, password} do
      {"user", "my p4ssw0rd"} ->
        state = [local_name: local_name, hostname: hostname] ++ state
        {:reply, {:ok, local_name <> ":" <> hostname}, {:connected, state}}

      {"reserveduser", _} ->
        {:reply, {:error, :exclusive, "This username is reserved"}, state}
    end
  end

  @impl true
  def handle_call({:join_room, room_alias}, _from, state) do
    case room_alias do
      "#existing_room:example.org" -> {:reply, {:ok, "!existing_room_id:example.org"}, state}
    end
  end

  @impl true
  def handle_call({:dump_state}, _from, state) do
    {:reply, state, state}
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
      {MockMatrixClient, {MockIrcConnSupervisor, self()}},
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

  def matrix_client(sup) do
    {_, pid, _, _} = List.keyfind(Supervisor.which_children(sup), MockMatrixClient, 0)
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

  @cap_ls_302 "CAP * LS :account-tag draft/account-registration=before-connect extended-join labeled-response sasl=PLAIN\r\n"
  @cap_ls "CAP * LS :account-tag draft/account-registration extended-join labeled-response sasl\r\n"
  @isupport "005 * * CASEMAPPING=rfc3454 CHANLIMIT= CHANTYPES=#! :TARGMAX=JOIN:1,PART:1\r\n"

  setup do
    start_supervised!({Matrix2051.Config, []})
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
        assert msg == {:line, @isupport}
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

  def do_connection_registration(handler, capabilities \\ []) do
    send(handler, cmd("CAP LS 302"))

    receive do
      msg -> assert msg == {:line, @cap_ls_302}
    end

    joined_caps = Enum.join(["sasl", "labeled-response"] ++ capabilities, " ")
    send(handler, cmd("CAP REQ :" <> joined_caps))

    receive do
      msg -> assert msg == {:line, "CAP * ACK :" <> joined_caps <> "\r\n"}
    end

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("@label=reg01 AUTHENTICATE PLAIN"))

    receive do
      msg -> assert msg == {:line, "@label=reg01 AUTHENTICATE :+\r\n"}
    end

    send(
      handler,
      cmd(
        "@label=reg02 AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk"
      )
    )

    receive do
      msg ->
        assert msg ==
                 {:line,
                  "@label=reg02 900 * * foo:example.org :You are now logged in as foo:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "@label=reg02 903 * :Authentication successful\r\n"}
    end

    send(handler, cmd("CAP END"))
    assert_welcome()
  end

  test "non-IRCv3 connection registration with no authenticate", %{handler: handler} do
    send(handler, cmd("NICK foo:example.org"))

    send(handler, cmd("PING sync1"))

    receive do
      msg -> assert msg == {:line, "PONG :sync1\r\n"}
    end

    send(handler, cmd("USER ident * * :My GECOS"))

    receive do
      msg -> assert msg == {:line, "ERROR :You must authenticate.\r\n"}
    end

    receive do
      msg -> assert msg == {:close}
    end
  end

  test "IRCv3 connection registration with no SASL", %{handler: handler} do
    send(handler, cmd("CAP LS"))

    receive do
      msg -> assert msg == {:line, @cap_ls}
    end

    send(handler, cmd("PING sync1"))

    receive do
      msg -> assert msg == {:line, "PONG :sync1\r\n"}
    end

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("CAP END"))

    receive do
      msg -> assert msg == {:line, "ERROR :You must authenticate.\r\n"}
    end

    receive do
      msg -> assert msg == {:close}
    end
  end

  test "IRCv3 connection registration with no authenticate", %{handler: handler} do
    send(handler, cmd("CAP LS"))

    receive do
      msg -> assert msg == {:line, @cap_ls}
    end

    send(handler, cmd("CAP REQ sasl"))

    receive do
      msg -> assert msg == {:line, "CAP * ACK :sasl\r\n"}
    end

    send(handler, cmd("PING sync1"))

    receive do
      msg -> assert msg == {:line, "PONG :sync1\r\n"}
    end

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("CAP END"))

    receive do
      msg -> assert msg == {:line, "ERROR :You must authenticate.\r\n"}
    end

    receive do
      msg -> assert msg == {:close}
    end
  end

  test "Connection registration", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS 302"))

    receive do
      msg -> assert msg == {:line, @cap_ls_302}
    end

    send(handler, cmd("CAP REQ sasl"))

    receive do
      msg -> assert msg == {:line, "CAP * ACK :sasl\r\n"}
    end

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("AUTHENTICATE PLAIN"))

    receive do
      msg -> assert msg == {:line, "AUTHENTICATE :+\r\n"}
    end

    # foo:example.org\x00foo:example.org\x00correct password
    send(
      handler,
      cmd("AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk")
    )

    receive do
      msg ->
        assert msg ==
                 {:line, "900 * * foo:example.org :You are now logged in as foo:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "903 * :Authentication successful\r\n"}
    end

    send(handler, cmd("CAP END"))
    assert_welcome()

    assert Matrix2051.IrcConn.State.nick(state) == "foo:example.org"
    assert Matrix2051.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "Registration with mismatched nick", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS 302"))

    receive do
      msg -> assert msg == {:line, @cap_ls_302}
    end

    send(handler, cmd("CAP REQ sasl"))

    receive do
      msg -> assert msg == {:line, "CAP * ACK :sasl\r\n"}
    end

    send(handler, cmd("NICK initial_nick"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("AUTHENTICATE PLAIN"))

    receive do
      msg -> assert msg == {:line, "AUTHENTICATE :+\r\n"}
    end

    # foo:example.org\x00foo:example.org\x00correct password
    send(
      handler,
      cmd("AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk")
    )

    receive do
      msg ->
        assert msg ==
                 {:line, "900 * * foo:example.org :You are now logged in as foo:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "903 * :Authentication successful\r\n"}
    end

    send(handler, cmd("CAP END"))
    assert_welcome()

    receive do
      msg -> assert msg == {:line, ":initial_nick NICK :foo:example.org\r\n"}
    end

    assert Matrix2051.IrcConn.State.nick(state) == "foo:example.org"
    assert Matrix2051.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "user_id validation", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS"))

    receive do
      msg -> assert msg == {:line, @cap_ls}
    end

    send(handler, cmd("CAP REQ sasl"))

    receive do
      msg -> assert msg == {:line, "CAP * ACK :sasl\r\n"}
    end

    send(handler, cmd("NICK foo:bar"))
    send(handler, cmd("USER ident * * :My GECOS"))

    try_userid = fn userid, expected_message ->
      send(handler, cmd("AUTHENTICATE PLAIN"))

      receive do
        msg -> assert msg == {:line, "AUTHENTICATE :+\r\n"}
      end

      send(
        handler,
        cmd(
          "AUTHENTICATE " <>
            Base.encode64(userid <> "\x00" <> userid <> "\x00" <> "correct password")
        )
      )

      receive do
        msg ->
          assert msg == {:line, expected_message}
      end
    end

    try_userid.(
      "foo",
      "904 * :Invalid account/user id: must contain a colon (':'), to separate the username and hostname. For example: foo:matrix.org\r\n"
    )

    try_userid.(
      "foo:bar:baz",
      "904 * :Invalid account/user id: must not contain more than one colon.\r\n"
    )

    try_userid.(
      "foo bar:baz",
      "904 * :Invalid account/user id: your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/\r\n"
    )

    try_userid.(
      "café:baz",
      "904 * :Invalid account/user id: your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/\r\n"
    )

    try_userid.(
      "café:baz",
      "904 * :Invalid account/user id: your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/\r\n"
    )

    try_userid.(
      "foo:bar",
      "900 * * foo:bar :You are now logged in as foo:bar\r\n"
    )

    receive do
      msg -> assert msg == {:line, "903 * :Authentication successful\r\n"}
    end

    send(handler, cmd("CAP END"))

    assert_welcome()

    send(handler, cmd("PING sync2"))

    receive do
      msg -> assert msg == {:line, "PONG :sync2\r\n"}
    end

    assert Matrix2051.IrcConn.State.nick(state) == "foo:bar"
    assert Matrix2051.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "Account registration", %{handler: handler} do
    send(handler, cmd("CAP LS 302"))

    receive do
      msg -> assert msg == {:line, @cap_ls_302}
    end

    send(handler, cmd("CAP REQ sasl"))

    receive do
      msg -> assert msg == {:line, "CAP * ACK :sasl\r\n"}
    end

    send(handler, cmd("NICK user:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("REGISTER * * :my p4ssw0rd"))

    receive do
      msg ->
        assert msg ==
                 {:line,
                  "REGISTER SUCCESS user:example.org :You are now registered as user:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg ==
                 {:line,
                  "900 * * user:example.org :You are now logged in as user:example.org\r\n"}
    end

    send(handler, cmd("CAP END"))

    assert_welcome()
  end

  test "Labeled response", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=abcd PING sync1"))

    receive do
      msg -> assert msg == {:line, "@label=abcd PONG :sync1\r\n"}
    end
  end

  test "joining a room", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=abcd JOIN #existing_room:example.org"))

    receive do
      msg -> assert msg == {:line, "@label=abcd ACK\r\n"}
    end
  end
end
