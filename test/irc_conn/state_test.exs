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
