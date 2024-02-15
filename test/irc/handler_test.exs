##
# Copyright (C) 2021-2022  Valentin Lorentz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License version 3,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
###

defmodule M51.IrcConn.HandlerTest do
  use ExUnit.Case, async: false
  doctest M51.IrcConn.Handler

  @cap_ls_302 ":server. CAP * LS :account-tag batch draft/account-registration=before-connect draft/channel-rename draft/chathistory draft/message-redaction draft/multiline=max-bytes=8192 draft/no-implicit-names draft/sasl-ir echo-message extended-join labeled-response message-tags sasl=PLAIN server-time soju.im/account-required standard-replies userhost-in-names\r\n"
  @cap_ls ":server. CAP * LS :account-tag batch draft/account-registration draft/channel-rename draft/chathistory draft/message-redaction draft/multiline draft/no-implicit-names draft/sasl-ir echo-message extended-join labeled-response message-tags sasl server-time soju.im/account-required standard-replies userhost-in-names\r\n"
  @isupport "CASEMAPPING=rfc3454 CLIENTTAGDENY=*,-draft/react,-draft/reply CHANLIMIT= CHANMODES=b,,,i CHANTYPES=#! CHATHISTORY=100 LINELEN=8192 MAXTARGETS=1 MSGREFTYPES=msgid PREFIX= TARGMAX=JOIN:1,PART:1 UTF8ONLY :are supported by this server\r\n"

  setup do
    start_supervised!({MockMatrixClient, {self()}})
    state = start_supervised!({M51.IrcConn.State, {self()}})

    handler = start_supervised!({M51.IrcConn.Handler, {self()}})

    start_supervised!({MockIrcConnWriter, {self()}})
    start_supervised!({MockMatrixState, {self()}})

    %{
      state: state,
      handler: handler
    }
  end

  def cmd(line) do
    {:ok, command} = M51.Irc.Command.parse(line)
    command
  end

  defp assert_message(expected) do
    receive do
      msg ->
        assert msg == expected
    end
  end

  defp assert_line(line) do
    assert_message({:line, line})
  end

  defp assert_open_batch() do
    receive do
      msg ->
        {:line, line} = msg
        {:ok, cmd} = M51.Irc.Command.parse(line)
        %M51.Irc.Command{command: "BATCH", params: [param1 | _]} = cmd
        batch_id = String.slice(param1, 1, String.length(param1))
        {batch_id, line}
    end
  end

  def assert_welcome(nick) do
    assert_line(":server. 001 #{nick} :Welcome to this Matrix bouncer.\r\n")
    assert_line(":server. 005 #{nick} #{@isupport}")
    assert_line(":server. 375 #{nick} :- Message of the day\r\n")
    assert_line(":server. 372 #{nick} :Welcome to Matrix2051, a Matrix bouncer.\r\n")
    assert_line(":server. 372 #{nick} :\r\n")

    assert_line(
      ":server. 372 #{nick} :This program is free software. You may find its source\r\n"
    )

    assert_line(":server. 372 #{nick} :code at the following address:\r\n")
    assert_line(":server. 372 #{nick} :\r\n")
    assert_line(":server. 372 #{nick} :http://example.org/source.git\r\n")
    assert_line(":server. 372 #{nick} :\r\n")
    assert_line(":server. 376 #{nick} :End of /MOTD command.\r\n")
  end

  def do_connection_registration(handler, capabilities \\ []) do
    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    joined_caps = Enum.join(["batch", "labeled-response", "sasl"] ++ capabilities, " ")
    send(handler, cmd("CAP REQ :" <> joined_caps))
    assert_line(":server. CAP * ACK :" <> joined_caps <> "\r\n")

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("@label=reg01 AUTHENTICATE PLAIN"))
    assert_line("@label=reg01 AUTHENTICATE :+\r\n")

    send(
      handler,
      cmd(
        "@label=reg02 AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk"
      )
    )

    assert_line(
      "@label=reg02 :server. 900 foo:example.org foo:example.org!foo@example.org foo:example.org :You are now logged in as foo:example.org\r\n"
    )

    assert_line("@label=reg02 :server. 903 foo:example.org :Authentication successful\r\n")

    send(handler, cmd("CAP END"))
    assert_welcome("foo:example.org")
  end

  test "non-IRCv3 connection registration with no authenticate", %{handler: handler} do
    send(handler, cmd("NICK foo:example.org"))

    send(handler, cmd("PING sync1"))
    assert_line("PONG server. :sync1\r\n")

    send(handler, cmd("USER ident * * :My GECOS"))
    assert_line("FAIL * ACCOUNT_REQUIRED :You must authenticate.\r\n")
    assert_message({:close})
  end

  test "IRCv3 connection registration with no SASL", %{handler: handler} do
    send(handler, cmd("CAP LS"))
    assert_line(@cap_ls)

    send(handler, cmd("PING sync1"))
    assert_line("PONG server. :sync1\r\n")

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("CAP END"))
    assert_line("FAIL * ACCOUNT_REQUIRED :You must authenticate.\r\n")
    assert_message({:close})
  end

  test "IRCv3 connection registration with no authenticate", %{handler: handler} do
    send(handler, cmd("CAP LS"))
    assert_line(@cap_ls)

    send(handler, cmd("CAP REQ sasl"))
    assert_line(":server. CAP * ACK :sasl\r\n")

    send(handler, cmd("PING sync1"))
    assert_line("PONG server. :sync1\r\n")

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("CAP END"))
    assert_line("FAIL * ACCOUNT_REQUIRED :You must authenticate.\r\n")
    assert_message({:close})
  end

  test "Connection registration", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    send(handler, cmd("CAP REQ sasl"))
    assert_line(":server. CAP * ACK :sasl\r\n")

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("AUTHENTICATE PLAIN"))
    assert_line("AUTHENTICATE :+\r\n")

    # foo:example.org\x00foo:example.org\x00correct password
    send(
      handler,
      cmd("AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk")
    )

    assert_line(
      ":server. 900 foo:example.org foo:example.org!foo@example.org foo:example.org :You are now logged in as foo:example.org\r\n"
    )

    assert_line(":server. 903 foo:example.org :Authentication successful\r\n")

    send(handler, cmd("CAP END"))
    assert_welcome("foo:example.org")

    assert M51.IrcConn.State.nick(state) == "foo:example.org"
    assert M51.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "Connection registration with SASL-IR", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    send(handler, cmd("CAP REQ sasl"))
    assert_line(":server. CAP * ACK :sasl\r\n")

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    # foo:example.org\x00foo:example.org\x00correct password
    send(
      handler,
      cmd("AUTHENTICATE PLAIN Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk")
    )

    assert_line(
      ":server. 900 foo:example.org foo:example.org!foo@example.org foo:example.org :You are now logged in as foo:example.org\r\n"
    )

    assert_line(":server. 903 foo:example.org :Authentication successful\r\n")

    send(handler, cmd("CAP END"))
    assert_welcome("foo:example.org")

    assert M51.IrcConn.State.nick(state) == "foo:example.org"
    assert M51.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "Connection registration with AUTHENTICATE before NICK", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    send(handler, cmd("CAP REQ sasl"))
    assert_line(":server. CAP * ACK :sasl\r\n")

    send(handler, cmd("AUTHENTICATE PLAIN"))
    assert_line("AUTHENTICATE :+\r\n")

    # foo:example.org\x00foo:example.org\x00correct password
    send(
      handler,
      cmd("AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk")
    )

    assert_line(":server. 900 * * foo:example.org :You are now logged in as foo:example.org\r\n")

    assert_line(":server. 903 * :Authentication successful\r\n")

    send(handler, cmd("NICK foo:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("CAP END"))
    assert_welcome("foo:example.org")

    assert M51.IrcConn.State.nick(state) == "foo:example.org"
    assert M51.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "Registration with mismatched nick", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    send(handler, cmd("CAP REQ sasl"))
    assert_line(":server. CAP * ACK :sasl\r\n")

    send(handler, cmd("NICK initial_nick"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("AUTHENTICATE PLAIN"))
    assert_line("AUTHENTICATE :+\r\n")

    # foo:example.org\x00foo:example.org\x00correct password
    send(
      handler,
      cmd("AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk")
    )

    assert_line(
      ":server. 900 initial_nick initial_nick!foo@example.org foo:example.org :You are now logged in as foo:example.org\r\n"
    )

    assert_line(":server. 903 initial_nick :Authentication successful\r\n")

    send(handler, cmd("CAP END"))
    assert_welcome("initial_nick")
    assert_line(":initial_nick!foo@example.org NICK :foo:example.org\r\n")

    assert M51.IrcConn.State.nick(state) == "foo:example.org"
    assert M51.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "user_id validation", %{state: state, handler: handler} do
    send(handler, cmd("CAP LS"))
    assert_line(@cap_ls)

    send(handler, cmd("CAP REQ sasl"))
    assert_line(":server. CAP * ACK :sasl\r\n")

    send(handler, cmd("NICK foo:bar"))
    send(handler, cmd("USER ident * * :My GECOS"))

    try_userid = fn userid, expected_message ->
      send(handler, cmd("AUTHENTICATE PLAIN"))
      assert_line("AUTHENTICATE :+\r\n")

      send(
        handler,
        cmd(
          "AUTHENTICATE " <>
            Base.encode64(userid <> "\x00" <> userid <> "\x00" <> "correct password")
        )
      )

      assert_line(expected_message)
    end

    try_userid.(
      "foo",
      ":server. 904 foo:bar :Invalid account/user id: must contain a colon (':'), to separate the username and hostname. For example: foo:matrix.org\r\n"
    )

    try_userid.(
      "foo:bar:baz:qux",
      ":server. 904 foo:bar :Invalid account/user id: must not contain more than two colons.\r\n"
    )

    try_userid.(
      "foo:bar:baz",
      ":server. 904 foo:bar :Invalid account/user id: \"baz\" is not a valid port number\r\n"
    )

    try_userid.(
      "foo bar:baz",
      ":server. 904 foo:bar :Invalid account/user id: your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/\r\n"
    )

    try_userid.(
      "café:baz",
      ":server. 904 foo:bar :Invalid account/user id: your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/\r\n"
    )

    try_userid.(
      "café:baz",
      ":server. 904 foo:bar :Invalid account/user id: your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/\r\n"
    )

    try_userid.(
      "foo:bar",
      ":server. 900 foo:bar foo:bar!foo@bar foo:bar :You are now logged in as foo:bar\r\n"
    )

    assert_line(":server. 903 foo:bar :Authentication successful\r\n")

    send(handler, cmd("CAP END"))

    assert_welcome("foo:bar")

    send(handler, cmd("PING sync2"))
    assert_line(":server. PONG server. :sync2\r\n")

    assert M51.IrcConn.State.nick(state) == "foo:bar"
    assert M51.IrcConn.State.gecos(state) == "My GECOS"
  end

  test "Account registration", %{handler: handler} do
    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    send(handler, cmd("CAP REQ sasl"))
    assert_line(":server. CAP * ACK :sasl\r\n")

    send(handler, cmd("NICK user:example.org"))
    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("REGISTER * * :my p4ssw0rd"))

    assert_line(
      "REGISTER SUCCESS user:example.org :You are now registered as user:example.org\r\n"
    )

    assert_line(
      ":server. 900 user:example.org user:example.org!user@example.org user:example.org :You are now logged in as user:example.org\r\n"
    )

    send(handler, cmd("CAP END"))

    assert_welcome("user:example.org")
  end

  test "unknown errors during registration", %{handler: handler} do
    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    joined_caps = Enum.join(["batch", "labeled-response", "sasl"], " ")
    send(handler, cmd("CAP REQ :" <> joined_caps))
    assert_line(":server. CAP * ACK :" <> joined_caps <> "\r\n")

    send(handler, cmd("NICK foo:example.org"))

    # cause an error
    Logger.remove_backend(:console)
    send(handler, %M51.Irc.Command{tags: %{"label" => "abcd"}, command: "PING", params: [:foo]})

    receive do
      msg ->
        {:line, line} = msg

        assert Regex.match?(
                 ~r/@label=abcd :server. 400 \* PING :An unknown error occured, please report it along with your IRC and console logs. Summary:[^\r\n]*ArgumentError[^\r\n]*\r\n/,
                 line
               )
    end

    Logger.add_backend(:console)

    # make sure everything proceeds normally afterward

    send(handler, cmd("USER ident * * :My GECOS"))

    send(handler, cmd("@label=reg01 AUTHENTICATE PLAIN"))
    assert_line("@label=reg01 AUTHENTICATE :+\r\n")

    send(
      handler,
      cmd(
        "@label=reg02 AUTHENTICATE Zm9vOmV4YW1wbGUub3JnAGZvbzpleGFtcGxlLm9yZwBjb3JyZWN0IHBhc3N3b3Jk"
      )
    )

    assert_line(
      "@label=reg02 :server. 900 foo:example.org foo:example.org!foo@example.org foo:example.org :You are now logged in as foo:example.org\r\n"
    )

    assert_line("@label=reg02 :server. 903 foo:example.org :Authentication successful\r\n")

    send(handler, cmd("CAP END"))
    assert_welcome("foo:example.org")
  end

  test "unknown errors after registration", %{handler: handler} do
    do_connection_registration(handler)

    Logger.remove_backend(:console)

    send(handler, %M51.Irc.Command{tags: %{"label" => "abcd"}, command: "PING", params: [:foo]})

    receive do
      msg ->
        {:line, line} = msg

        assert Regex.match?(
                 ~r/@label=abcd :server. 400 foo:example.org PING :An unknown error occured, please report it along with your IRC and console logs. Summary:[^\r\n]*ArgumentError[^\r\n]*\r\n/,
                 line
               )
    end

    Logger.add_backend(:console)
  end

  test "post-registration CAP LS", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("CAP LS 302"))
    assert_line(@cap_ls_302)

    send(handler, cmd("CAP LS"))
    assert_line(@cap_ls)
  end

  test "post-registration CAP LIST", %{handler: handler} do
    caps_requested = ["draft/multiline", "extended-join", "message-tags", "server-time"]
    caps_expected = Enum.join(["batch", "labeled-response", "sasl"] ++ caps_requested, " ")

    do_connection_registration(handler, caps_requested)

    send(handler, cmd("CAP LIST"))
    assert_line(":server. CAP * LIST :" <> caps_expected <> "\r\n")
  end

  test "labeled response", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=abcd PING sync1"))
    assert_line("@label=abcd :server. PONG server. :sync1\r\n")
  end

  test "joining a room", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=abcd JOIN #existing_room:example.org"))
    assert_line("@label=abcd ACK\r\n")
  end

  test "joining multiple rooms", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=abcd JOIN #room1:example.org,#room2:example.org"))

    assert_line(
      "@label=abcd :server. 476 foo:example.org #room1:example.org,#room2:example.org :commas are not allowed in channel names (ISUPPORT MAXTARGETS/TARGMAX not implemented?)\r\n"
    )
  end

  test "ignores TAGMSG", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("TAGMSG #"))

    send(handler, cmd("PING sync1"))
    assert_line(":server. PONG server. :sync1\r\n")
  end

  test "sending privmsg", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("PRIVMSG #existing_room:example.org :hello world"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{"body" => "hello world", "msgtype" => "m.text"}}
    )
  end

  test "sending formatted privmsg", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("PRIVMSG #existing_room:example.org :\x02hello \x1dworld\x1d\x02"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{
         "body" => "*hello /world/*",
         "format" => "org.matrix.custom.html",
         "formatted_body" => "<b>hello </b><i><b>world</b></i>",
         "msgtype" => "m.text"
       }}
    )
  end

  test "sending privmsg + ACTION", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("PRIVMSG #existing_room:example.org :\x01ACTION says hello\x01"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{"body" => "says hello", "msgtype" => "m.emote"}}
    )
  end

  test "sending notice", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("NOTICE #existing_room:example.org :hello world"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{"body" => "hello world", "msgtype" => "m.notice"}}
    )
  end

  test "sending privmsg with label", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=foo PRIVMSG #existing_room:example.org :hello world"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", "foo",
       %{"body" => "hello world", "msgtype" => "m.text"}}
    )
  end

  test "sending multiline privmsg", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("BATCH +tag draft/multiline #existing_room:example.org"))
    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :hello"))
    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :world"))
    send(handler, cmd("@batch=tag;draft/multiline-concat PRIVMSG #existing_room:example.org :!"))
    send(handler, cmd("BATCH -tag"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{"body" => "hello\nworld!", "msgtype" => "m.text"}}
    )
  end

  test "sending multiline privmsg + ACTION", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("BATCH +tag draft/multiline #existing_room:example.org"))
    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :\x01ACTION says"))
    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :hello"))

    send(
      handler,
      cmd("@batch=tag;draft/multiline-concat PRIVMSG #existing_room:example.org :!\x01")
    )

    send(handler, cmd("BATCH -tag"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{"body" => "says\nhello!", "msgtype" => "m.emote"}}
    )
  end

  test "sending multiline notice", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("BATCH +tag draft/multiline #existing_room:example.org"))
    send(handler, cmd("@batch=tag NOTICE #existing_room:example.org :hello"))
    send(handler, cmd("@batch=tag NOTICE #existing_room:example.org :world"))
    send(handler, cmd("@batch=tag;draft/multiline-concat NOTICE #existing_room:example.org :!"))
    send(handler, cmd("BATCH -tag"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{"body" => "hello\nworld!", "msgtype" => "m.notice"}}
    )
  end

  test "sending multiline privmsg with label", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=foo BATCH +tag draft/multiline #existing_room:example.org"))
    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :hello"))
    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :world"))
    send(handler, cmd("@batch=tag;draft/multiline-concat PRIVMSG #existing_room:example.org :!"))
    send(handler, cmd("BATCH -tag"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", "foo",
       %{"body" => "hello\nworld!", "msgtype" => "m.text"}}
    )
  end

  test "sending privmsg reply", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@+draft/reply=$event1 PRIVMSG #existing_room:example.org :hello world"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{
         "body" => "hello world",
         "msgtype" => "m.text",
         "m.relates_to" => %{
           "m.in_reply_to" => %{
             "event_id" => "$event1"
           }
         }
       }}
    )
  end

  test "sending privmsg + ACTION reply", %{handler: handler} do
    do_connection_registration(handler)

    send(
      handler,
      cmd("@+draft/reply=$event1 PRIVMSG #existing_room:example.org :\x01ACTION says hello\x01")
    )

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{
         "body" => "says hello",
         "msgtype" => "m.emote",
         "m.relates_to" => %{
           "m.in_reply_to" => %{
             "event_id" => "$event1"
           }
         }
       }}
    )
  end

  test "sending notice reply", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@+draft/reply=$event1 NOTICE #existing_room:example.org :hello world"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{
         "body" => "hello world",
         "msgtype" => "m.notice",
         "m.relates_to" => %{
           "m.in_reply_to" => %{
             "event_id" => "$event1"
           }
         }
       }}
    )
  end

  test "sending multiline privmsg reply", %{handler: handler} do
    do_connection_registration(handler)

    send(
      handler,
      cmd("@+draft/reply=$event1 BATCH +tag draft/multiline #existing_room:example.org")
    )

    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :hello"))
    send(handler, cmd("@batch=tag PRIVMSG #existing_room:example.org :world"))
    send(handler, cmd("@batch=tag;draft/multiline-concat PRIVMSG #existing_room:example.org :!"))
    send(handler, cmd("BATCH -tag"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.room.message", nil,
       %{
         "body" => "hello\nworld!",
         "msgtype" => "m.text",
         "m.relates_to" => %{
           "m.in_reply_to" => %{
             "event_id" => "$event1"
           }
         }
       }}
    )
  end

  test "sending reacts", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@+draft/reply=$event1;+draft/react=👍 TAGMSG #existing_room:example.org"))

    assert_message(
      {:send_event, "#existing_room:example.org", "m.reaction", nil,
       %{
         "m.relates_to" => %{
           "rel_type" => "m.annotation",
           "event_id" => "$event1",
           "key" => "👍"
         }
       }}
    )
  end

  test "WHO o on channel", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 WHO #nonexistant_room:example.org o"))

    assert_line(
      "@label=l1 :server. 315 foo:example.org #nonexistant_room:example.org :End of WHO list\r\n"
    )

    send(handler, cmd("@label=l2 WHO #existing_room:example.org o"))

    assert_line(
      "@label=l2 :server. 315 foo:example.org #existing_room:example.org :End of WHO list\r\n"
    )
  end

  test "WHO on channel", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 WHO #nonexistant_room:example.org"))

    # No reply because the room is not synced (and never will be)
    send(handler, cmd("PING sync1"))
    assert_line(":server. PONG server. :sync1\r\n")

    send(handler, cmd("@label=l2 WHO #existing_room:example.org"))

    {batch_id, line} = assert_open_batch()
    assert line == "@label=l2 BATCH +#{batch_id} :labeled-response\r\n"

    assert_line(
      "@batch=#{batch_id} :server. 352 foo:example.org #existing_room:example.org user1 example.org * user1:example.org H :0 user one\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 352 foo:example.org #existing_room:example.org user2 example.com * user2:example.com H :0 user2:example.com\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 315 foo:example.org #existing_room:example.org :End of WHO list\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "WHO on channel without label", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("WHO #nonexistant_room:example.org"))

    # No reply because the room is not synced (and never will be)
    send(handler, cmd("PING sync1"))
    assert_line(":server. PONG server. :sync1\r\n")

    send(handler, cmd("WHO #existing_room:example.org"))

    assert_line(
      ":server. 352 foo:example.org #existing_room:example.org user1 example.org * user1:example.org H :0 user one\r\n"
    )

    assert_line(
      ":server. 352 foo:example.org #existing_room:example.org user2 example.com * user2:example.com H :0 user2:example.com\r\n"
    )

    assert_line(":server. 315 foo:example.org #existing_room:example.org :End of WHO list\r\n")
  end

  test "WHO on user", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 WHO otheruser:example.org"))

    {batch_id, line} = assert_open_batch()
    assert line == "@label=l1 BATCH +#{batch_id} :labeled-response\r\n"

    assert_line(
      "@batch=#{batch_id} :server. 352 foo:example.org * otheruser example.org * otheruser:example.org H :0 otheruser:example.org\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 315 foo:example.org otheruser:example.org :End of WHO list\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "WHOIS known user", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 WHOIS user1:example.org"))

    {batch_id, line} = assert_open_batch()
    assert line == "@label=l1 BATCH +#{batch_id} :labeled-response\r\n"

    assert_line(
      "@batch=#{batch_id} :server. 311 foo:example.org user1:example.org user1 example.org * :user one\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 319 foo:example.org user1:example.org :#existing_room:example.org\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 312 foo:example.org user1:example.org example.org :example.org\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 330 foo:example.org user1:example.org user1:example.org :is logged in as\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 318 foo:example.org user1:example.org :End of WHOIS\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "WHOIS unknown user", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 WHOIS unknown_user:example.com"))

    {batch_id, line} = assert_open_batch()
    assert line == "@label=l1 BATCH +#{batch_id} :labeled-response\r\n"

    assert_line(
      "@batch=#{batch_id} :server. 311 foo:example.org unknown_user:example.com unknown_user example.com * :unknown_user:example.com\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 312 foo:example.org unknown_user:example.com example.com :example.com\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 330 foo:example.org unknown_user:example.com unknown_user:example.com :is logged in as\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :server. 318 foo:example.org unknown_user:example.com :End of WHOIS\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "WHOIS non-MXID", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 WHOIS not_enough_colons"))

    assert_line("@label=l1 :server. 401 foo:example.org not_enough_colons :No such nick\r\n")

    send(handler, cmd("@label=l1 WHOIS :with spaces"))

    assert_line("@label=l1 :server. 401 foo:example.org * :No such nick\r\n")
  end

  test "MODE on user", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 MODE unknown_user:example.com"))

    assert_line("@label=l1 :server. 502 foo:example.org :Can't view mode of other users\r\n")

    send(handler, cmd("@label=l2 MODE foo:example.org"))

    assert_line("@label=l2 :server. 221 foo:example.org :+i\r\n")

    send(handler, cmd("@label=l3 MODE unknown_user:example.com +i"))

    assert_line("@label=l3 :server. 502 foo:example.org :Can't set mode of other users\r\n")

    send(handler, cmd("@label=l4 MODE foo:example.org +i"))

    assert_line(
      "@label=l4 :server. 501 foo:example.org :Setting user modes are not supported\r\n"
    )
  end

  test "MODE on channel", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("@label=l1 MODE #unknown_channel:example.com"))

    assert_line("@label=l1 :server. 324 foo:example.org #unknown_channel:example.com :+nt\r\n")

    send(handler, cmd("@label=l2 MODE !unknown_channel:example.com"))

    assert_line("@label=l2 :server. 324 foo:example.org !unknown_channel:example.com :+nt\r\n")

    send(handler, cmd("@label=l3 MODE #unknown_channel:example.com +i"))

    assert_line(
      "@label=l3 :server. 482 foo:example.org #unknown_channel:example.com :You're not a channel operator\r\n"
    )

    send(handler, cmd("@label=l4 MODE !unknown_channel:example.com +i"))

    assert_line(
      "@label=l4 :server. 482 foo:example.org !unknown_channel:example.com :You're not a channel operator\r\n"
    )
  end

  test "CHATHISTORY AROUND", %{handler: handler} do
    do_connection_registration(handler, ["message-tags"])

    send(handler, cmd("@label=l1 CHATHISTORY AROUND #chan msgid=$event3 5"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l1 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #chan :first message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #chan :second message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #chan :third message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event4 :nick:example.org!nick@example.org PRIVMSG #chan :fourth message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event5 :nick:example.org!nick@example.org PRIVMSG #chan :fifth message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")

    send(handler, cmd("@label=l2 CHATHISTORY AROUND #chan msgid=$event3 4"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l2 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #chan :first message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #chan :second message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #chan :third message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event4 :nick:example.org!nick@example.org PRIVMSG #chan :fourth message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")

    send(handler, cmd("@label=l3 CHATHISTORY AROUND #chan msgid=$event3 3"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l3 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #chan :second message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #chan :third message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event4 :nick:example.org!nick@example.org PRIVMSG #chan :fourth message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")

    send(handler, cmd("@label=l4 CHATHISTORY AROUND #chan msgid=$event3 2"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l4 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #chan :second message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #chan :third message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")

    send(handler, cmd("@label=l5 CHATHISTORY AROUND #chan msgid=$event3 1"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l5 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #chan :third message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "CHATHISTORY BEFORE", %{handler: handler} do
    do_connection_registration(handler, ["message-tags"])

    send(handler, cmd("@label=l1 CHATHISTORY BEFORE #chan msgid=$event3 2"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l1 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #chan :first message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #chan :second message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")

    send(handler, cmd("@label=l2 CHATHISTORY BEFORE #chan msgid=$event3 1"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l2 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #chan :second message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "CHATHISTORY LATEST", %{handler: handler} do
    do_connection_registration(handler, ["message-tags"])

    send(handler, cmd("@label=l2 CHATHISTORY LATEST #chan * 1"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l2 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event5 :nick:example.org!nick@example.org PRIVMSG #chan :fifth message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")

    send(handler, cmd("@label=l1 CHATHISTORY LATEST #chan * 2"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l1 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event4 :nick:example.org!nick@example.org PRIVMSG #chan :fourth message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event5 :nick:example.org!nick@example.org PRIVMSG #chan :fifth message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "CHATHISTORY AFTER", %{handler: handler} do
    do_connection_registration(handler, ["message-tags"])

    send(handler, cmd("@label=l1 CHATHISTORY AFTER #chan msgid=$event3 2"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l1 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event4 :nick:example.org!nick@example.org PRIVMSG #chan :fourth message\r\n"
    )

    assert_line(
      "@batch=#{batch_id};msgid=$event5 :nick:example.org!nick@example.org PRIVMSG #chan :fifth message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")

    send(handler, cmd("@label=l2 CHATHISTORY AFTER #chan msgid=$event3 1"))
    {batch_id, line} = assert_open_batch()
    assert line == "@label=l2 BATCH +#{batch_id} :chathistory\r\n"

    assert_line(
      "@batch=#{batch_id};msgid=$event4 :nick:example.org!nick@example.org PRIVMSG #chan :fourth message\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
  end

  test "redact a message for no reason", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("REDACT #existing_room:example.org $event1"))

    assert_message({:send_redact, "#existing_room:example.org", nil, "$event1", nil})
  end

  test "redact a message for a reason", %{handler: handler} do
    do_connection_registration(handler)

    send(handler, cmd("REDACT #existing_room:example.org $event1 :spam"))

    assert_message({:send_redact, "#existing_room:example.org", nil, "$event1", "spam"})
  end
end
