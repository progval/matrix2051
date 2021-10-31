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

defmodule M51.MatrixClient.StateTest do
  use ExUnit.Case
  doctest M51.MatrixClient.State

  setup do
    start_supervised!({M51.MatrixClient.State, {nil}})
    |> Process.register(:process_matrix_state)

    :ok
  end

  test "canonical alias" do
    M51.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!foo:example.org",
      "#alias1:example.org"
    )

    assert M51.MatrixClient.State.room_canonical_alias(
             :process_matrix_state,
             "!foo:example.org"
           ) == "#alias1:example.org"

    M51.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!foo:example.org",
      "#alias2:example.org"
    )

    assert M51.MatrixClient.State.room_canonical_alias(
             :process_matrix_state,
             "!foo:example.org"
           ) == "#alias2:example.org"
  end

  test "default canonical alias" do
    assert M51.MatrixClient.State.room_canonical_alias(
             :process_matrix_state,
             "!foo:example.org"
           ) == nil
  end

  test "room members" do
    M51.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!foo:example.org",
      "user1:example.com",
      %M51.Matrix.RoomMember{display_name: "user one"}
    )

    assert M51.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             %{"user1:example.com" => %M51.Matrix.RoomMember{display_name: "user one"}}

    M51.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!foo:example.org",
      "user2:example.com",
      %M51.Matrix.RoomMember{display_name: nil}
    )

    assert M51.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             %{
               "user1:example.com" => %M51.Matrix.RoomMember{display_name: "user one"},
               "user2:example.com" => %M51.Matrix.RoomMember{display_name: nil}
             }

    M51.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!foo:example.org",
      "user2:example.com",
      %M51.Matrix.RoomMember{display_name: nil}
    )

    assert M51.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             %{
               "user1:example.com" => %M51.Matrix.RoomMember{display_name: "user one"},
               "user2:example.com" => %M51.Matrix.RoomMember{display_name: nil}
             }

    M51.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!bar:example.org",
      "user1:example.com",
      %M51.Matrix.RoomMember{display_name: nil}
    )

    assert M51.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             %{
               "user1:example.com" => %M51.Matrix.RoomMember{display_name: "user one"},
               "user2:example.com" => %M51.Matrix.RoomMember{display_name: nil}
             }

    assert M51.MatrixClient.State.room_members(:process_matrix_state, "!bar:example.org") ==
             %{"user1:example.com" => %M51.Matrix.RoomMember{display_name: nil}}
  end

  test "default room members" do
    assert M51.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") == %{}
  end

  test "irc channel" do
    assert M51.MatrixClient.State.room_irc_channel(
             :process_matrix_state,
             "!foo:example.org"
           ) == "!foo:example.org"

    M51.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!foo:example.org",
      "#alias1:example.org"
    )

    assert M51.MatrixClient.State.room_irc_channel(
             :process_matrix_state,
             "!foo:example.org"
           ) == "#alias1:example.org"

    M51.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!bar:example.org",
      "#alias2:example.org"
    )

    {room_id, _} =
      M51.MatrixClient.State.room_from_irc_channel(
        :process_matrix_state,
        "#alias1:example.org"
      )

    assert room_id == "!foo:example.org"

    {room_id, _} =
      M51.MatrixClient.State.room_from_irc_channel(
        :process_matrix_state,
        "#alias2:example.org"
      )

    assert room_id == "!bar:example.org"

    assert M51.MatrixClient.State.room_from_irc_channel(
             :process_matrix_state,
             "!roomid:example.org"
           ) == nil
  end

  test "runs callbacks on sync" do
    pid = self()

    M51.MatrixClient.State.queue_on_channel_sync(
      :process_matrix_state,
      "!room:example.org",
      fn room_id, _room -> send(pid, {:synced1, room_id}) end
    )

    M51.MatrixClient.State.queue_on_channel_sync(
      :process_matrix_state,
      "#chan:example.org",
      fn room_id, _room -> send(pid, {:synced2, room_id}) end
    )

    M51.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!room:example.org",
      "#chan:example.org"
    )

    M51.MatrixClient.State.mark_synced(:process_matrix_state, "!room:example.org")

    receive do
      msg -> assert msg == {:synced1, "!room:example.org"}
    end

    receive do
      msg -> assert msg == {:synced2, "!room:example.org"}
    end
  end

  test "runs callbacks immediately when already synced" do
    pid = self()

    M51.MatrixClient.State.mark_synced(:process_matrix_state, "!room:example.org")

    M51.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!room:example.org",
      "#chan:example.org"
    )

    M51.MatrixClient.State.queue_on_channel_sync(
      :process_matrix_state,
      "!room:example.org",
      fn room_id, _room -> send(pid, {:synced1, room_id}) end
    )

    receive do
      msg -> assert msg == {:synced1, "!room:example.org"}
    end

    M51.MatrixClient.State.queue_on_channel_sync(
      :process_matrix_state,
      "#chan:example.org",
      fn room_id, _room -> send(pid, {:synced2, room_id}) end
    )

    receive do
      msg -> assert msg == {:synced2, "!room:example.org"}
    end
  end

  test "runs callbacks on canonical alias when already synced" do
    pid = self()

    M51.MatrixClient.State.queue_on_channel_sync(
      :process_matrix_state,
      "#chan:example.org",
      fn room_id, _room -> send(pid, {:synced2, room_id}) end
    )

    M51.MatrixClient.State.mark_synced(:process_matrix_state, "!room:example.org")

    M51.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!room:example.org",
      "#chan:example.org"
    )

    receive do
      msg -> assert msg == {:synced2, "!room:example.org"}
    end
  end
end
