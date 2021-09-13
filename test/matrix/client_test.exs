defmodule Matrix2051.MatrixClientTest do
  use ExUnit.Case
  doctest Matrix2051.MatrixClient

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    config = start_supervised!({Matrix2051.Config, [matrix_id: "user:matrix.example.org"]})
    %{config: config}
  end

  test "initialization without well-known" do
    MockHTTPoison
    |> expect(:get!, fn _url ->
      %HTTPoison.Response{
        status_code: 404,
        body: """
          {
            "m.homeserver": {
              "base_url": "https://matrix.example.com"
            }
          }
        """
      }
    end)

    client = start_supervised!({Matrix2051.MatrixClient, [httpoison: MockHTTPoison]})

    assert GenServer.call(client, {:dump_state}) ==
             {MockHTTPoison, "user:matrix.example.org", "https://matrix.example.org"}
  end

  test "initialization with well-known" do
    MockHTTPoison
    |> expect(:get!, fn _url ->
      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
            "m.homeserver": {
              "base_url": "https://matrix.example.com"
            }
          }
        """
      }
    end)

    client = start_supervised!({Matrix2051.MatrixClient, [httpoison: MockHTTPoison]})

    assert GenServer.call(client, {:dump_state}) ==
             {MockHTTPoison, "user:matrix.example.org", "https://matrix.example.com"}
  end
end
