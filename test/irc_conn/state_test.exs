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

defmodule M51.IrcConn.StateTest do
  use ExUnit.Case
  doctest M51.IrcConn.State

  test "batches" do
    state = start_supervised!({M51.IrcConn.State, {nil}})

    opening_command = %M51.Irc.Command{
      command: "BATCH",
      params: ["+tag", "type", "foo", "bar"]
    }

    M51.IrcConn.State.create_batch(state, "tag", opening_command)
    M51.IrcConn.State.add_batch_command(state, "tag", :foo)
    M51.IrcConn.State.add_batch_command(state, "tag", :bar)
    M51.IrcConn.State.add_batch_command(state, "tag", :baz)

    assert M51.IrcConn.State.pop_batch(state, "tag") == {opening_command, [:foo, :bar, :baz]}
  end
end
