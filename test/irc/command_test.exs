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

defmodule M51.Irc.CommandTest do
  use ExUnit.Case
  doctest M51.Irc.Command

  test "default values" do
    assert M51.Irc.Command.parse("PRIVMSG #chan :hello\r\n") ==
             {:ok,
              %M51.Irc.Command{
                tags: %{},
                source: nil,
                command: "PRIVMSG",
                params: ["#chan", "hello"]
              }}
  end

  test "parse leniently" do
    assert M51.Irc.Command.parse("@msgid=foo    :nick!user@host   privMSG  #chan   :hello\n") ==
             {:ok,
              %M51.Irc.Command{
                tags: %{"msgid" => "foo"},
                source: "nick!user@host",
                command: "PRIVMSG",
                params: ["#chan", "hello"]
              }}
  end

  test "parse numeric" do
    assert M51.Irc.Command.parse("001 welcome\r\n") ==
             {:ok,
              %M51.Irc.Command{
                command: "001",
                params: ["welcome"]
              }}
  end

  test "format numeric" do
    assert M51.Irc.Command.format(%M51.Irc.Command{
             command: "001",
             params: ["welcome"]
           }) == "001 :welcome\r\n"
  end

  test "format invalid characters" do
    assert M51.Irc.Command.format(%M51.Irc.Command{
             source: "foo\0bar\rbaz\nqux:example.org!foo\\0bar\\rbaz\\nqux@example.org",
             command: "PRIVMSG",
             params: ["#room:example.org", "hi there"]
           }) ==
             ":foo\\0bar\\rbaz\\nqux:example.org!foo\\0bar\\rbaz\\nqux@example.org PRIVMSG #room:example.org :hi there\r\n"

    assert M51.Irc.Command.format(%M51.Irc.Command{
             source: "foo bar:example.org!foo bar@example.org",
             command: "PRIVMSG",
             params: ["#bad room:example.org", "hi there"]
           }) ==
             ":foo\\sbar:example.org!foo\\sbar@example.org PRIVMSG #bad\\sroom:example.org :hi there\r\n"
  end

  test "escape message tags" do
    assert M51.Irc.Command.format(%M51.Irc.Command{
             tags: %{"foo" => "semi;space backslash\\cr\rlf\ndone", "bar" => "baz"},
             command: "TAGMSG",
             params: ["#chan"]
           }) == "@bar=baz;foo=semi\\:space\\sbackslash\\\\cr\\rlf\\ndone TAGMSG :#chan\r\n"
  end

  test "unescape message tags" do
    assert M51.Irc.Command.parse(
             "@bar=baz;foo=semi\\:space\\sbackslash\\\\cr\\rlf\\ndone TAGMSG :#chan\r\n"
           ) ==
             {:ok,
              %M51.Irc.Command{
                tags: %{"foo" => "semi;space backslash\\cr\rlf\ndone", "bar" => "baz"},
                command: "TAGMSG",
                params: ["#chan"]
              }}
  end

  test "downgrade noop" do
    assert M51.Irc.Command.downgrade(
             %M51.Irc.Command{
               command: "001",
               params: ["welcome"]
             },
             []
           ) == %M51.Irc.Command{
             command: "001",
             params: ["welcome"]
           }
  end

  test "downgrade label" do
    cmd = %M51.Irc.Command{
      tags: %{"label" => "abcd"},
      command: "PONG",
      params: ["foo"]
    }

    assert M51.Irc.Command.downgrade(cmd, []) == %M51.Irc.Command{
             command: "PONG",
             params: ["foo"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:labeled_response]) == cmd
  end

  test "downgrade ack" do
    cmd = %M51.Irc.Command{
      tags: %{"label" => "abcd"},
      command: "ACK",
      params: []
    }

    assert M51.Irc.Command.downgrade(cmd, []) == nil

    assert M51.Irc.Command.downgrade(cmd, [:labeled_response]) == cmd
  end

  test "drop ack without label" do
    cmd = %M51.Irc.Command{
      command: "ACK",
      params: []
    }

    assert M51.Irc.Command.downgrade(cmd, []) == nil

    assert M51.Irc.Command.downgrade(cmd, [:labeled_response]) == nil
  end

  test "downgrade account-tag" do
    cmd = %M51.Irc.Command{
      tags: %{"account" => "abcd"},
      command: "PRIVMSG",
      params: ["#foo", "bar"]
    }

    assert M51.Irc.Command.downgrade(cmd, []) == %M51.Irc.Command{
             command: "PRIVMSG",
             params: ["#foo", "bar"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:account_tag]) == cmd
  end

  test "downgrade client tags" do
    cmd = %M51.Irc.Command{
      tags: %{"+foo" => "bar"},
      source: "nick",
      command: "PRIVMSG",
      params: ["#foo", "hi"]
    }

    assert M51.Irc.Command.downgrade(cmd, []) == %M51.Irc.Command{
             source: "nick",
             command: "PRIVMSG",
             params: ["#foo", "hi"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:message_tags]) == cmd
  end

  test "downgrade TAGMSG" do
    cmd = %M51.Irc.Command{
      tags: %{"+foo" => "bar"},
      source: "nick",
      command: "TAGMSG",
      params: ["#foo"]
    }

    assert M51.Irc.Command.downgrade(cmd, []) == nil

    assert M51.Irc.Command.downgrade(cmd, [:message_tags]) == cmd
  end

  test "downgrade extended-join" do
    cmd = %M51.Irc.Command{
      source: "nick",
      command: "JOIN",
      params: ["#foo", "account", "realname"]
    }

    assert M51.Irc.Command.downgrade(cmd, []) == %M51.Irc.Command{
             source: "nick",
             command: "JOIN",
             params: ["#foo"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:extended_join]) == cmd
  end

  test "downgrade extended-join and/or account-tag" do
    cmd = %M51.Irc.Command{
      tags: %{"account" => "abcd"},
      command: "JOIN",
      params: ["#foo", "account", "realname"]
    }

    assert M51.Irc.Command.downgrade(cmd, []) == %M51.Irc.Command{
             tags: %{},
             command: "JOIN",
             params: ["#foo"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:extended_join]) == %M51.Irc.Command{
             tags: %{},
             command: "JOIN",
             params: ["#foo", "account", "realname"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:account_tag]) == %M51.Irc.Command{
             tags: %{"account" => "abcd"},
             command: "JOIN",
             params: ["#foo"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:account_tag, :extended_join]) == cmd
    assert M51.Irc.Command.downgrade(cmd, [:extended_join, :account_tag]) == cmd
  end

  test "downgrade echo-message and/or label" do
    cmd = %M51.Irc.Command{
      tags: %{"label" => "abcd"},
      command: "PRIVMSG",
      params: ["#foo", "bar"],
      is_echo: true
    }

    assert M51.Irc.Command.downgrade(cmd, []) == nil
    assert M51.Irc.Command.downgrade(cmd, [:labeled_response]) == nil

    assert M51.Irc.Command.downgrade(cmd, [:echo_message]) == %M51.Irc.Command{
             tags: %{},
             command: "PRIVMSG",
             params: ["#foo", "bar"],
             is_echo: true
           }

    assert M51.Irc.Command.downgrade(cmd, [:labeled_response, :echo_message]) == cmd
    assert M51.Irc.Command.downgrade(cmd, [:echo_message, :labeled_response]) == cmd
  end

  test "downgrade echo-message without label" do
    cmd = %M51.Irc.Command{
      command: "PRIVMSG",
      params: ["#foo", "bar"],
      is_echo: true
    }

    assert M51.Irc.Command.downgrade(cmd, []) == nil
    assert M51.Irc.Command.downgrade(cmd, [:labeled_response]) == nil

    assert M51.Irc.Command.downgrade(cmd, [:echo_message]) == %M51.Irc.Command{
             tags: %{},
             command: "PRIVMSG",
             params: ["#foo", "bar"],
             is_echo: true
           }

    assert M51.Irc.Command.downgrade(cmd, [:labeled_response, :echo_message]) == cmd
    assert M51.Irc.Command.downgrade(cmd, [:echo_message, :labeled_response]) == cmd
  end

  test "downgrade userhost-in-names" do
    cmd = %M51.Irc.Command{
      source: "server",
      # RPL_NAMREPLY
      command: "353",
      params: [
        "nick",
        "=",
        "#foo",
        "nick:example.org!nick@example.org nick2:example.org!nick2@example.org"
      ]
    }

    assert M51.Irc.Command.downgrade(cmd, []) == %M51.Irc.Command{
             source: "server",
             command: "353",
             params: ["nick", "=", "#foo", "nick:example.org nick2:example.org"]
           }

    assert M51.Irc.Command.downgrade(cmd, [:userhost_in_names]) == cmd
  end

  test "linewrap" do
    assert M51.Irc.Command.linewrap(
             %M51.Irc.Command{
               command: "PRIVMSG",
               params: ["#chan", "hello world"]
             },
             25
           ) == [
             %M51.Irc.Command{
               tags: %{},
               source: nil,
               command: "PRIVMSG",
               params: ["#chan", "hello "]
             },
             %M51.Irc.Command{
               tags: %{"draft/multiline-concat" => nil},
               source: nil,
               command: "PRIVMSG",
               params: ["#chan", "world"]
             }
           ]
  end
end
