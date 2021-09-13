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
end
