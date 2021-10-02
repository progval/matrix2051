defmodule MockIrcSupervisor do
  def matrix_poller(pid) do
    pid
  end
end

defmodule Matrix2051.MatrixClient.ClientTest do
  use ExUnit.Case
  doctest Matrix2051.MatrixClient.Client

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    config = start_supervised!({Matrix2051.Config, []})
    %{config: config, irc_pid: self()}
  end

  def expect_login(mock_httpoison) do
    mock_httpoison
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"
      %HTTPoison.Response{status_code: 404, body: "Error 404"}
    end)
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {"flows": [{"type": "m.login.password"}]}
        """
      }
    end)
    |> expect(:post!, fn url, body ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "user" => "user",
               "password" => "p4ssw0rd"
             }

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
              "access_token": "t0ken",
              "home_server": "matrix.example.org",
              "user_id": "@user:matrix.example.org"
          }
        """
      }
    end)
  end

  test "initialization", %{irc_pid: irc_pid} do
    irc_mod = MockIrcSupervisor

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client, {irc_mod, irc_pid, [httpoison: MockHTTPoison]}}
      )

    assert GenServer.call(client, {:dump_state}) ==
             %Matrix2051.MatrixClient.Client{
               state: :initial_state,
               irc_mod: irc_mod,
               irc_pid: irc_pid,
               args: [httpoison: MockHTTPoison]
             }
  end

  test "connection without well-known", %{irc_pid: irc_pid} do
    MockHTTPoison
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"

      %HTTPoison.Response{
        status_code: 404,
        body: """
          Error 404
        """
      }
    end)
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
              "flows": [
                  {
                      "type": "m.login.password"
                  }
              ]
          }
        """
      }
    end)
    |> expect(:post!, fn url, body ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "user" => "user",
               "password" => "p4ssw0rd"
             }

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
              "access_token": "t0ken",
              "home_server": "matrix.example.org",
              "user_id": "@user:matrix.example.org"
          }
        """
      }
    end)

    irc_mod = MockIrcSupervisor

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client, {irc_mod, irc_pid, [httpoison: MockHTTPoison]}}
      )

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) == {:ok}

    assert GenServer.call(client, {:dump_state}) ==
             %Matrix2051.MatrixClient.Client{
               state: :connected,
               irc_mod: irc_mod,
               irc_pid: irc_pid,
               raw_client: %Matrix2051.Matrix.RawClient{
                 base_url: "https://matrix.example.org",
                 access_token: "t0ken",
                 httpoison: MockHTTPoison
               },
               rooms: Map.new(),
               local_name: "user",
               hostname: "matrix.example.org"
             }

    assert Matrix2051.MatrixClient.Client.user_id(client) == "user:matrix.example.org"

    receive do
      msg -> assert msg == :connected
    end
  end

  test "connection with well-known", %{irc_pid: irc_pid} do
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
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.com/_matrix/client/r0/login"

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
              "flows": [
                  {
                      "type": "m.login.token"
                  },
                  {
                      "type": "m.login.password"
                  }
              ]
          }
        """
      }
    end)
    |> expect(:post!, fn url, body ->
      assert url == "https://matrix.example.com/_matrix/client/r0/login"

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "user" => "user",
               "password" => "p4ssw0rd"
             }

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
              "access_token": "t0ken",
              "home_server": "matrix.example.org",
              "user_id": "@user:matrix.example.org"
          }
        """
      }
    end)

    irc_mod = MockIrcSupervisor

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client, {irc_mod, irc_pid, [httpoison: MockHTTPoison]}}
      )

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) == {:ok}

    assert GenServer.call(client, {:dump_state}) ==
             %Matrix2051.MatrixClient.Client{
               state: :connected,
               irc_mod: irc_mod,
               irc_pid: irc_pid,
               raw_client: %Matrix2051.Matrix.RawClient{
                 base_url: "https://matrix.example.com",
                 access_token: "t0ken",
                 httpoison: MockHTTPoison
               },
               rooms: Map.new(),
               local_name: "user",
               hostname: "matrix.example.org"
             }

    assert Matrix2051.MatrixClient.Client.user_id(client) == "user:matrix.example.org"

    receive do
      msg -> assert msg == :connected
    end
  end

  test "connection without password flow", %{irc_pid: irc_pid} do
    MockHTTPoison
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"

      %HTTPoison.Response{
        status_code: 404,
        body: """
          Error 404
        """
      }
    end)
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
              "flows": [
                  {
                      "type": "m.login.token"
                  }
              ]
          }
        """
      }
    end)

    irc_mod = MockIrcSupervisor

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client, {irc_mod, irc_pid, [httpoison: MockHTTPoison]}}
      )

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) ==
             {:error, :no_password_flow, "No password flow"}

    assert GenServer.call(client, {:dump_state}) ==
             %Matrix2051.MatrixClient.Client{
               state: :initial_state,
               irc_mod: irc_mod,
               irc_pid: irc_pid,
               args: [httpoison: MockHTTPoison]
             }

    assert Matrix2051.MatrixClient.Client.user_id(client) == nil
  end

  test "connection with invalid password", %{irc_pid: irc_pid} do
    MockHTTPoison
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"

      %HTTPoison.Response{
        status_code: 404,
        body: """
          Error 404
        """
      }
    end)
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {
              "flows": [
                  {
                      "type": "m.login.password"
                  }
              ]
          }
        """
      }
    end)
    |> expect(:post!, fn url, body ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "user" => "user",
               "password" => "p4ssw0rd"
             }

      %HTTPoison.Response{
        status_code: 403,
        body: """
          {"errcode": "M_FORBIDDEN", "error": "Invalid password"}
        """
      }
    end)

    irc_mod = MockIrcSupervisor

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client, {irc_mod, irc_pid, [httpoison: MockHTTPoison]}}
      )

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) ==
             {:error, :denied, "Invalid password"}

    assert GenServer.call(client, {:dump_state}) ==
             %Matrix2051.MatrixClient.Client{
               state: :initial_state,
               irc_mod: irc_mod,
               irc_pid: irc_pid,
               args: [httpoison: MockHTTPoison]
             }

    assert Matrix2051.MatrixClient.Client.user_id(client) == nil
  end

  test "registration", %{irc_pid: irc_pid} do
    MockHTTPoison
    |> expect(:get!, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"
      %HTTPoison.Response{status_code: 404, body: "Error 404"}
    end)
    |> expect(:post!, fn url, body ->
      assert url == "https://matrix.example.org/_matrix/client/r0/register"

      assert Jason.decode!(body) == %{
               "username" => "user",
               "password" => "p4ssw0rd",
               "auth" => %{"type" => "m.login.dummy"}
             }

      %HTTPoison.Response{
        status_code: 200,
        body: """
        {
            "access_token": "t0ken",
            "home_server": "matrix.example.org",
            "user_id": "@user:matrix.example.org"
        }
        """
      }
    end)

    irc_mod = MockIrcSupervisor

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client, {irc_mod, irc_pid, [httpoison: MockHTTPoison]}}
      )

    assert GenServer.call(client, {:register, "user", "matrix.example.org", "p4ssw0rd"}) ==
             {:ok, "user:matrix.example.org"}

    assert GenServer.call(client, {:dump_state}) ==
             %Matrix2051.MatrixClient.Client{
               state: :connected,
               irc_mod: irc_mod,
               irc_pid: irc_pid,
               raw_client: %Matrix2051.Matrix.RawClient{
                 base_url: "https://matrix.example.org",
                 access_token: "t0ken",
                 httpoison: MockHTTPoison
               },
               rooms: Map.new(),
               local_name: "user",
               hostname: "matrix.example.org"
             }

    assert Matrix2051.MatrixClient.Client.user_id(client) == "user:matrix.example.org"

    receive do
      msg -> assert msg == :connected
    end
  end

  test "joining a room", %{irc_pid: irc_pid} do
    MockHTTPoison
    |> expect_login
    |> expect(:post!, fn url, body, headers ->
      assert headers == [Authorization: "Bearer t0ken"]

      assert url ==
               "https://matrix.example.org/_matrix/client/r0/join/%23testroom%3Amatrix.example.com"

      assert Jason.decode!(body) == %{}
      %HTTPoison.Response{status_code: 200, body: "{\"room_id\": \"!abc:matrix.example.net\"}"}
    end)

    irc_mod = MockIrcSupervisor

    client =
      start_supervised!(
        {Matrix2051.MatrixClient.Client, {irc_mod, irc_pid, [httpoison: MockHTTPoison]}}
      )

    assert Matrix2051.MatrixClient.Client.connect(
             client,
             "user",
             "matrix.example.org",
             "p4ssw0rd"
           ) == {:ok}

    receive do
      msg -> assert msg == :connected
    end

    assert Matrix2051.MatrixClient.Client.join_room(client, "#testroom:matrix.example.com")
  end
end
