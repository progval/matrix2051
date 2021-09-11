defmodule Matrix2051.Irc.CommandTest do
  use ExUnit.Case
  doctest Matrix2051.Irc.Command

  test "default values" do
    assert Matrix2051.Irc.Command.parse("PRIVMSG #chan :hello\r\n") ==
             {:ok,
              %Matrix2051.Irc.Command{
                tags: %{},
                origin: nil,
                command: "PRIVMSG",
                params: ["#chan", "hello"]
              }}
  end

  test "lenient" do
    assert Matrix2051.Irc.Command.parse(
             "@msgid=foo    :nick!user@host   privMSG  #chan   :hello\n"
           ) ==
             {:ok,
              %Matrix2051.Irc.Command{
                tags: %{"msgid" => "foo"},
                origin: "nick!user@host",
                command: "PRIVMSG",
                params: ["#chan", "hello"]
              }}
  end

  test "numeric" do
    assert Matrix2051.Irc.Command.parse("001 welcome\r\n") ==
             {:ok,
              %Matrix2051.Irc.Command{
                command: "001",
                params: ["welcome"]
              }}
  end
end
