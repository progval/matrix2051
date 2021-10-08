defmodule Matrix2051.Irc.CommandTest do
  use ExUnit.Case
  doctest Matrix2051.Irc.Command

  test "default values" do
    assert Matrix2051.Irc.Command.parse("PRIVMSG #chan :hello\r\n") ==
             {:ok,
              %Matrix2051.Irc.Command{
                tags: %{},
                source: nil,
                command: "PRIVMSG",
                params: ["#chan", "hello"]
              }}
  end

  test "parse leniently" do
    assert Matrix2051.Irc.Command.parse(
             "@msgid=foo    :nick!user@host   privMSG  #chan   :hello\n"
           ) ==
             {:ok,
              %Matrix2051.Irc.Command{
                tags: %{"msgid" => "foo"},
                source: "nick!user@host",
                command: "PRIVMSG",
                params: ["#chan", "hello"]
              }}
  end

  test "parse numeric" do
    assert Matrix2051.Irc.Command.parse("001 welcome\r\n") ==
             {:ok,
              %Matrix2051.Irc.Command{
                command: "001",
                params: ["welcome"]
              }}
  end

  test "numeric" do
    assert Matrix2051.Irc.Command.format(%Matrix2051.Irc.Command{
             command: "001",
             params: ["welcome"]
           }) == "001 :welcome\r\n"
  end

  test "downgrade noop" do
    assert Matrix2051.Irc.Command.downgrade(
             %Matrix2051.Irc.Command{
               command: "001",
               params: ["welcome"]
             },
             []
           ) == %Matrix2051.Irc.Command{
             command: "001",
             params: ["welcome"]
           }
  end

  test "downgrade label" do
    cmd = %Matrix2051.Irc.Command{
      tags: %{"label" => "abcd"},
      command: "PONG",
      params: ["foo"]
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == %Matrix2051.Irc.Command{
             command: "PONG",
             params: ["foo"]
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:labeled_response]) == cmd
  end

  test "downgrade ack" do
    cmd = %Matrix2051.Irc.Command{
      tags: %{"label" => "abcd"},
      command: "ACK",
      params: []
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == nil

    assert Matrix2051.Irc.Command.downgrade(cmd, [:labeled_response]) == cmd
  end

  test "downgrade account-tag" do
    cmd = %Matrix2051.Irc.Command{
      tags: %{"account" => "abcd"},
      command: "PRIVMSG",
      params: ["#foo", "bar"]
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == %Matrix2051.Irc.Command{
             command: "PRIVMSG",
             params: ["#foo", "bar"]
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:account_tag]) == cmd
  end

  test "downgrade extended-join" do
    cmd = %Matrix2051.Irc.Command{
      source: "nick",
      command: "JOIN",
      params: ["#foo", "account", "realname"]
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == %Matrix2051.Irc.Command{
             source: "nick",
             command: "JOIN",
             params: ["#foo"]
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:extended_join]) == cmd
  end

  test "downgrade extended-join and/or account-tag" do
    cmd = %Matrix2051.Irc.Command{
      tags: %{"account" => "abcd"},
      command: "JOIN",
      params: ["#foo", "account", "realname"],
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == %Matrix2051.Irc.Command{
             tags: %{},
             command: "JOIN",
             params: ["#foo"]
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:extended_join]) == %Matrix2051.Irc.Command{
             tags: %{},
             command: "JOIN",
             params: ["#foo", "account", "realname"]
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:account_tag]) == %Matrix2051.Irc.Command{
             tags: %{"account" => "abcd"},
             command: "JOIN",
             params: ["#foo"]
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:account_tag, :extended_join]) == cmd
    assert Matrix2051.Irc.Command.downgrade(cmd, [:extended_join, :account_tag]) == cmd
  end

  test "downgrade echo-message and/or label" do
    cmd = %Matrix2051.Irc.Command{
      tags: %{"label" => "abcd"},
      command: "PRIVMSG",
      params: ["#foo", "bar"],
      is_echo: true
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == nil
    assert Matrix2051.Irc.Command.downgrade(cmd, [:labeled_response]) == nil

    assert Matrix2051.Irc.Command.downgrade(cmd, [:echo_message]) == %Matrix2051.Irc.Command{
             tags: %{},
             command: "PRIVMSG",
             params: ["#foo", "bar"],
             is_echo: true
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:labeled_response, :echo_message]) == cmd
    assert Matrix2051.Irc.Command.downgrade(cmd, [:echo_message, :labeled_response]) == cmd
  end

  test "downgrade echo-message without label" do
    cmd = %Matrix2051.Irc.Command{
      command: "PRIVMSG",
      params: ["#foo", "bar"],
      is_echo: true
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == nil
    assert Matrix2051.Irc.Command.downgrade(cmd, [:labeled_response]) == nil

    assert Matrix2051.Irc.Command.downgrade(cmd, [:echo_message]) == %Matrix2051.Irc.Command{
             tags: %{},
             command: "PRIVMSG",
             params: ["#foo", "bar"],
             is_echo: true
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:labeled_response, :echo_message]) == cmd
    assert Matrix2051.Irc.Command.downgrade(cmd, [:echo_message, :labeled_response]) == cmd
  end
end
