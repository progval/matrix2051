defmodule Matrix2051.MatrixClient.StateTest do
  use ExUnit.Case
  doctest Matrix2051.MatrixClient.State

  setup do
    start_supervised!({Matrix2051.MatrixClient.State, {}})
    |> Process.register(:process_matrix_state)

    :ok
  end

  test "canonical alias" do
    Matrix2051.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!foo:example.org",
      "#alias1:example.org"
    )

    assert Matrix2051.MatrixClient.State.room_canonical_alias(
             :process_matrix_state,
             "!foo:example.org"
           ) == "#alias1:example.org"

    Matrix2051.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!foo:example.org",
      "#alias2:example.org"
    )

    assert Matrix2051.MatrixClient.State.room_canonical_alias(
             :process_matrix_state,
             "!foo:example.org"
           ) == "#alias2:example.org"
  end

  test "default canonical alias" do
    assert Matrix2051.MatrixClient.State.room_canonical_alias(
             :process_matrix_state,
             "!foo:example.org"
           ) == nil
  end

  test "room members" do
    Matrix2051.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!foo:example.org",
      "user1:example.com"
    )

    assert Matrix2051.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             MapSet.new(["user1:example.com"])

    Matrix2051.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!foo:example.org",
      "user2:example.com"
    )

    assert Matrix2051.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             MapSet.new(["user1:example.com", "user2:example.com"])

    Matrix2051.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!foo:example.org",
      "user2:example.com"
    )

    assert Matrix2051.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             MapSet.new(["user1:example.com", "user2:example.com"])

    Matrix2051.MatrixClient.State.room_member_add(
      :process_matrix_state,
      "!bar:example.org",
      "user1:example.com"
    )

    assert Matrix2051.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             MapSet.new(["user1:example.com", "user2:example.com"])

    assert Matrix2051.MatrixClient.State.room_members(:process_matrix_state, "!bar:example.org") ==
             MapSet.new(["user1:example.com"])
  end

  test "default room members" do
    assert Matrix2051.MatrixClient.State.room_members(:process_matrix_state, "!foo:example.org") ==
             MapSet.new()
  end

  test "irc channel" do
    assert Matrix2051.MatrixClient.State.room_irc_channel(
             :process_matrix_state,
             "!foo:example.org"
           ) == "!foo:example.org"

    Matrix2051.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!foo:example.org",
      "#alias1:example.org"
    )

    assert Matrix2051.MatrixClient.State.room_irc_channel(
             :process_matrix_state,
             "!foo:example.org"
           ) == "#alias1:example.org"

    Matrix2051.MatrixClient.State.set_room_canonical_alias(
      :process_matrix_state,
      "!bar:example.org",
      "#alias2:example.org"
    )

    {room_id, _} =
      Matrix2051.MatrixClient.State.room_from_irc_channel(
        :process_matrix_state,
        "#alias1:example.org"
      )

    assert room_id == "!foo:example.org"

    {room_id, _} =
      Matrix2051.MatrixClient.State.room_from_irc_channel(
        :process_matrix_state,
        "#alias2:example.org"
      )

    assert room_id == "!bar:example.org"

    assert Matrix2051.MatrixClient.State.room_from_irc_channel(
             :process_matrix_state,
             "!roomid:example.org"
           ) == nil
  end
end
