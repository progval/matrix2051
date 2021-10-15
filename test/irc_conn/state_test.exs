defmodule Matrix2051.IrcConn.StateTest do
  use ExUnit.Case
  doctest Matrix2051.IrcConn.State

  test "batches" do
    start_supervised!({Registry, keys: :unique, name: Matrix2051.Registry})
    state = start_supervised!({Matrix2051.IrcConn.State, {nil}})

    opening_command = %Matrix2051.Irc.Command{
      command: "BATCH",
      params: ["+tag", "type", "foo", "bar"]
    }

    Matrix2051.IrcConn.State.create_batch(state, "tag", opening_command)
    Matrix2051.IrcConn.State.add_batch_command(state, "tag", :foo)
    Matrix2051.IrcConn.State.add_batch_command(state, "tag", :bar)
    Matrix2051.IrcConn.State.add_batch_command(state, "tag", :baz)

    assert Matrix2051.IrcConn.State.pop_batch(state, "tag") ==
             {opening_command, [:foo, :bar, :baz]}
  end
end
