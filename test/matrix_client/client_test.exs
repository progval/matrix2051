##
# Copyright (C) 2021-2022  Valentin Lorentz
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

defmodule M51.MatrixClient.ClientTest do
  use ExUnit.Case
  doctest M51.MatrixClient.Client

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!

  @timeout 65000

  setup do
    start_supervised!({M51.MatrixClient.State, {self()}})

    Registry.register(M51.Registry, {self(), :matrix_poller}, self())

    %{sup_pid: self()}
  end

  def expect_login(mock_httpoison) do
    mock_httpoison
    |> expect(:get, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"
      {:ok, %HTTPoison.Response{status_code: 404, body: "Error 404"}}
    end)
    |> expect(:get!, fn url, headers, options ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

      %HTTPoison.Response{
        status_code: 200,
        body: """
          {"flows": [{"type": "m.login.password"}]}
        """
      }
    end)
    |> expect(:post!, fn url, body, headers, options ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "identifier" => %{
                 "type" => "m.id.user",
                 "user" => "user"
               },
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

  test "initialization", %{sup_pid: sup_pid} do
    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert GenServer.call(client, {:dump_state}) ==
             %M51.MatrixClient.Client{
               state: :initial_state,
               irc_pid: sup_pid,
               args: [httpoison: MockHTTPoison]
             }
  end

  test "connection to non-homeserver", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect(:get, fn url ->
      assert url == "https://example.org/.well-known/matrix/client"

      {:ok,
       %HTTPoison.Response{
         status_code: 404,
         body: """
           Error 404
         """
       }}
    end)
    |> expect(:get!, fn url, headers, options ->
      assert url == "https://example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

      %HTTPoison.Response{
        status_code: 404,
        body: """
          Error 404
        """
      }
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert {:error, :unknown, message} =
             GenServer.call(client, {:connect, "user", "example.org", "p4ssw0rd"})

    assert Regex.match?(~r/Could not reach the Matrix homeserver for example.org.*/, message)

    assert GenServer.call(client, {:dump_state}) ==
             %M51.MatrixClient.Client{
               state: :initial_state,
               irc_pid: sup_pid,
               args: [httpoison: MockHTTPoison]
             }
  end

  test "connection without well-known", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect(:get, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"

      {:ok,
       %HTTPoison.Response{
         status_code: 404,
         body: """
           Error 404
         """
       }}
    end)
    |> expect(:get!, fn url, headers, options ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

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
    |> expect(:post!, fn url, body, headers, options ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "identifier" => %{
                 "type" => "m.id.user",
                 "user" => "user"
               },
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

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) == {:ok}

    assert GenServer.call(client, {:dump_state}) ==
             %M51.MatrixClient.Client{
               state: :connected,
               irc_pid: sup_pid,
               raw_client: %M51.Matrix.RawClient{
                 base_url: "https://matrix.example.org",
                 access_token: "t0ken",
                 httpoison: MockHTTPoison
               },
               local_name: "user",
               hostname: "matrix.example.org"
             }

    assert M51.MatrixClient.Client.user_id(client) == "user:matrix.example.org"

    receive do
      msg -> assert msg == :connected
    end
  end

  test "connection with well-known", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect(:get, fn _url ->
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: """
           {
             "m.homeserver": {
               "base_url": "https://matrix.example.com"
             }
           }
         """
       }}
    end)
    |> expect(:get!, fn url, headers, options ->
      assert url == "https://matrix.example.com/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

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
    |> expect(:post!, fn url, body, headers, options ->
      assert url == "https://matrix.example.com/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "identifier" => %{
                 "type" => "m.id.user",
                 "user" => "user"
               },
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

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) == {:ok}

    assert GenServer.call(client, {:dump_state}) ==
             %M51.MatrixClient.Client{
               state: :connected,
               irc_pid: sup_pid,
               raw_client: %M51.Matrix.RawClient{
                 base_url: "https://matrix.example.com",
                 access_token: "t0ken",
                 httpoison: MockHTTPoison
               },
               local_name: "user",
               hostname: "matrix.example.org"
             }

    assert M51.MatrixClient.Client.user_id(client) == "user:matrix.example.org"

    receive do
      msg -> assert msg == :connected
    end
  end

  test "connection without password flow", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect(:get, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"

      {:ok,
       %HTTPoison.Response{
         status_code: 404,
         body: """
           Error 404
         """
       }}
    end)
    |> expect(:get!, fn url, headers, options ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

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

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) ==
             {:error, :no_password_flow, "No password flow"}

    assert GenServer.call(client, {:dump_state}) ==
             %M51.MatrixClient.Client{
               state: :initial_state,
               irc_pid: sup_pid,
               args: [httpoison: MockHTTPoison]
             }

    assert M51.MatrixClient.Client.user_id(client) == nil
  end

  test "connection with invalid password", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect(:get, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"

      {:ok,
       %HTTPoison.Response{
         status_code: 404,
         body: """
           Error 404
         """
       }}
    end)
    |> expect(:get!, fn url, headers, options ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

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
    |> expect(:post!, fn url, body, headers, options ->
      assert url == "https://matrix.example.org/_matrix/client/r0/login"
      assert headers == []
      assert options == [timeout: @timeout, recv_timeout: @timeout]

      assert Jason.decode!(body) == %{
               "type" => "m.login.password",
               "identifier" => %{
                 "type" => "m.id.user",
                 "user" => "user"
               },
               "password" => "p4ssw0rd"
             }

      %HTTPoison.Response{
        status_code: 403,
        body: """
          {"errcode": "M_FORBIDDEN", "error": "Invalid password"}
        """
      }
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert GenServer.call(client, {:connect, "user", "matrix.example.org", "p4ssw0rd"}) ==
             {:error, :denied, "Invalid password"}

    assert GenServer.call(client, {:dump_state}) ==
             %M51.MatrixClient.Client{
               state: :initial_state,
               irc_pid: sup_pid,
               args: [httpoison: MockHTTPoison]
             }

    assert M51.MatrixClient.Client.user_id(client) == nil
  end

  test "registration", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect(:get, fn url ->
      assert url == "https://matrix.example.org/.well-known/matrix/client"
      {:ok, %HTTPoison.Response{status_code: 404, body: "Error 404"}}
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

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert GenServer.call(client, {:register, "user", "matrix.example.org", "p4ssw0rd"}) ==
             {:ok, "user:matrix.example.org"}

    assert GenServer.call(client, {:dump_state}) ==
             %M51.MatrixClient.Client{
               state: :connected,
               irc_pid: sup_pid,
               raw_client: %M51.Matrix.RawClient{
                 base_url: "https://matrix.example.org",
                 access_token: "t0ken",
                 httpoison: MockHTTPoison
               },
               local_name: "user",
               hostname: "matrix.example.org"
             }

    assert M51.MatrixClient.Client.user_id(client) == "user:matrix.example.org"

    receive do
      msg -> assert msg == :connected
    end
  end

  test "joining a room", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect_login
    |> expect(:post, fn url, body, headers, _options ->
      assert headers == [Authorization: "Bearer t0ken"]

      assert url ==
               "https://matrix.example.org/_matrix/client/r0/join/%23testroom%3Amatrix.example.com"

      assert Jason.decode!(body) == %{}

      {:ok,
       %HTTPoison.Response{status_code: 200, body: "{\"room_id\": \"!abc:matrix.example.net\"}"}}
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert M51.MatrixClient.Client.connect(
             client,
             "user",
             "matrix.example.org",
             "p4ssw0rd"
           ) == {:ok}

    receive do
      msg -> assert msg == :connected
    end

    assert M51.MatrixClient.Client.join_room(client, "#testroom:matrix.example.com")
  end

  test "getting event context", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect_login
    |> expect(:get, fn url, headers, _options ->
      assert headers == [Authorization: "Bearer t0ken"]

      assert url ==
               "https://matrix.example.org/_matrix/client/r0/rooms/%21roomid%3Aexample.org/context/%24event3?limit=5"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: ~s({"events_before": [], "event": "foo", "events_after": []})
       }}
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    state = M51.IrcConn.Supervisor.matrix_state(sup_pid)

    M51.MatrixClient.State.set_room_canonical_alias(
      state,
      "!roomid:example.org",
      "#chan:example.org"
    )

    assert M51.MatrixClient.Client.connect(
             client,
             "user",
             "matrix.example.org",
             "p4ssw0rd"
           ) == {:ok}

    receive do
      msg -> assert msg == :connected
    end

    assert M51.MatrixClient.Client.get_event_context(
             client,
             "#chan:example.org",
             "$event3",
             5
           ) == {:ok, %{"event" => "foo", "events_after" => [], "events_before" => []}}
  end

  test "getting last events", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect_login
    |> expect(:get, fn url, headers, _options ->
      assert headers == [Authorization: "Bearer t0ken"]

      assert url ==
               "https://matrix.example.org/_matrix/client/v3/rooms/%21roomid%3Aexample.org/messages?dir=b&limit=5"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: ~s({"state": [], "chunk": []})
       }}
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    state = M51.IrcConn.Supervisor.matrix_state(sup_pid)

    M51.MatrixClient.State.set_room_canonical_alias(
      state,
      "!roomid:example.org",
      "#chan:example.org"
    )

    assert M51.MatrixClient.Client.connect(
             client,
             "user",
             "matrix.example.org",
             "p4ssw0rd"
           ) == {:ok}

    receive do
      msg -> assert msg == :connected
    end

    assert M51.MatrixClient.Client.get_latest_events(
             client,
             "#chan:example.org",
             5
           ) == {:ok, %{"state" => [], "chunk" => []}}
  end

  test "checking valid alias", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect_login
    |> expect(:get, fn url, headers, _options ->
      assert headers == [Authorization: "Bearer t0ken"]

      assert url ==
               "https://matrix.example.org/_matrix/client/r0/directory/room/%23validalias%3Aexample.org"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: ~s({"room_id": "!roomid:example.org"})
       }}
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert M51.MatrixClient.Client.connect(
             client,
             "user",
             "matrix.example.org",
             "p4ssw0rd"
           ) == {:ok}

    receive do
      msg -> assert msg == :connected
    end

    assert M51.MatrixClient.Client.valid_alias?(
             client,
             "!roomid:example.org",
             "#validalias:example.org"
           ) == true
  end

  test "checking nonexistent alias", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect_login
    |> expect(:get, fn url, headers, _options ->
      assert headers == [Authorization: "Bearer t0ken"]

      assert url ==
               "https://matrix.example.org/_matrix/client/r0/directory/room/%23validalias%3Aexample.org"

      {:ok,
       %HTTPoison.Response{
         status_code: 404,
         body: ~s({"foo": "bar"})
       }}
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert M51.MatrixClient.Client.connect(
             client,
             "user",
             "matrix.example.org",
             "p4ssw0rd"
           ) == {:ok}

    receive do
      msg -> assert msg == :connected
    end

    assert M51.MatrixClient.Client.valid_alias?(
             client,
             "!roomid:example.org",
             "#validalias:example.org"
           ) == false
  end

  test "checking alias to wrong room", %{sup_pid: sup_pid} do
    MockHTTPoison
    |> expect_login
    |> expect(:get, fn url, headers, _options ->
      assert headers == [Authorization: "Bearer t0ken"]

      assert url ==
               "https://matrix.example.org/_matrix/client/r0/directory/room/%23validalias%3Aexample.org"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: ~s({"room_id": "!otherroomid:example.org"})
       }}
    end)

    client = start_supervised!({M51.MatrixClient.Client, {sup_pid, [httpoison: MockHTTPoison]}})

    assert M51.MatrixClient.Client.connect(
             client,
             "user",
             "matrix.example.org",
             "p4ssw0rd"
           ) == {:ok}

    receive do
      msg -> assert msg == :connected
    end

    assert M51.MatrixClient.Client.valid_alias?(
             client,
             "!roomid:example.org",
             "#validalias:example.org"
           ) == false
  end
end
