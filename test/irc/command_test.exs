##
# Copyright (C) 2021  Valentin Lorentz
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

  test "format numeric" do
    assert Matrix2051.Irc.Command.format(%Matrix2051.Irc.Command{
             command: "001",
             params: ["welcome"]
           }) == "001 :welcome\r\n"
  end

  test "escape message tags" do
    assert Matrix2051.Irc.Command.format(%Matrix2051.Irc.Command{
             tags: %{"foo" => "semi;space backslash\\cr\rlf\ndone", "bar" => "baz"},
             command: "TAGMSG",
             params: ["#chan"]
           }) == "@bar=baz;foo=semi\\:space\\sbackslash\\\\cr\\rlf\\ndone TAGMSG :#chan\r\n"
  end

  test "unescape message tags" do
    assert Matrix2051.Irc.Command.parse(
             "@bar=baz;foo=semi\\:space\\sbackslash\\\\cr\\rlf\\ndone TAGMSG :#chan\r\n"
           ) ==
             {:ok,
              %Matrix2051.Irc.Command{
                tags: %{"foo" => "semi;space backslash\\cr\rlf\ndone", "bar" => "baz"},
                command: "TAGMSG",
                params: ["#chan"]
              }}
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

  test "drop ack without label" do
    cmd = %Matrix2051.Irc.Command{
      command: "ACK",
      params: []
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == nil

    assert Matrix2051.Irc.Command.downgrade(cmd, [:labeled_response]) == nil
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

  test "downgrade client tags" do
    cmd = %Matrix2051.Irc.Command{
      tags: %{"+foo" => "bar"},
      source: "nick",
      command: "PRIVMSG",
      params: ["#foo", "hi"]
    }

    assert Matrix2051.Irc.Command.downgrade(cmd, []) == %Matrix2051.Irc.Command{
             source: "nick",
             command: "PRIVMSG",
             params: ["#foo", "hi"]
           }

    assert Matrix2051.Irc.Command.downgrade(cmd, [:message_tags]) == cmd
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
      params: ["#foo", "account", "realname"]
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
