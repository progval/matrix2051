defmodule Matrix2051.MatrixClient.ClientTest do
  use ExUnit.Case
  doctest Matrix2051.MatrixClient.Client

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    config = start_supervised!({Matrix2051.Config, []})
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

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client,
         [httpoison: MockHTTPoison, local_name: "user", hostname: "matrix.example.org"]}
      )

    assert GenServer.call(client, {:dump_state}) ==
             {:state,
              {%Matrix2051.Matrix.RawClient{
                 base_url: "https://matrix.example.org",
                 httpoison: MockHTTPoison
               }, "user", "matrix.example.org"}}
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

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client,
         [httpoison: MockHTTPoison, local_name: "user", hostname: "matrix.example.org"]}
      )

    assert GenServer.call(client, {:dump_state}) ==
             {:state,
              {%Matrix2051.Matrix.RawClient{
                 base_url: "https://matrix.example.com",
                 httpoison: MockHTTPoison
               }, "user", "matrix.example.org"}}
  end
end
