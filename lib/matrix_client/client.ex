defmodule Matrix2051.MatrixClient.Client do
  @moduledoc """
    Manages connections to a Matrix homeserver.
  """
  use GenServer

  # The state of this client
  defstruct [
    # :initial_state or :connected
    :state,
    # extra keyword list passed to init/1
    :args,
    # IrcConnSupervisor
    :irc_mod,
    # pid of IrcConnSupervisor
    :irc_pid,
    # Matrix2051.Matrix.RawClient structure
    :raw_client,
    # room_alias -> room_id map
    :rooms,
    :local_name,
    :hostname
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(args) do
    {irc_mod, irc_pid, extra_args} = args

    {:ok,
     %Matrix2051.MatrixClient.Client{
       state: :initial_state,
       irc_mod: irc_mod,
       irc_pid: irc_pid,
       args: extra_args
     }}
  end

  @impl true
  def handle_call({:dump_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:connect, local_name, hostname, password}, _from, state) do
    case state do
      %Matrix2051.MatrixClient.Client{
        state: :initial_state,
        irc_mod: irc_mod,
        irc_pid: irc_pid,
        args: args
      } ->
        httpoison = Keyword.get(args, :httpoison, HTTPoison)
        base_url = get_base_url(hostname, httpoison)

        # Check the server supports password login
        %HTTPoison.Response{status_code: 200, body: body} =
          httpoison.get!(base_url <> "/_matrix/client/r0/login")

        data = Jason.decode!(body)

        flow =
          case data["flows"] do
            flows when is_list(flows) ->
              Enum.find(flows, nil, fn flow -> flow["type"] == "m.login.password" end)

            _ ->
              nil
          end

        case flow do
          nil ->
            {:reply, {:error, :no_password_flow, "No password flow"}, state}

          _ ->
            body =
              Jason.encode!(%{
                "type" => "m.login.password",
                "user" => local_name,
                "password" => password
              })

            case httpoison.post!(base_url <> "/_matrix/client/r0/login", body) do
              %HTTPoison.Response{status_code: 200, body: body} ->
                data = Jason.decode!(body)

                if data["user_id"] != "@" <> local_name <> ":" <> hostname do
                  raise "Unexpected user_id: " <> data["user_id"]
                end

                access_token = data["access_token"]

                raw_client = %Matrix2051.Matrix.RawClient{
                  base_url: base_url,
                  access_token: access_token,
                  httpoison: httpoison
                }

                state = %Matrix2051.MatrixClient.Client{
                  state: :connected,
                  irc_mod: irc_mod,
                  irc_pid: irc_pid,
                  raw_client: raw_client,
                  rooms: Map.new(),
                  local_name: local_name,
                  hostname: hostname
                }

                poller = irc_mod.matrix_poller(irc_pid)
                send(poller, :connected)

                {:reply, {:ok}, state}

              %HTTPoison.Response{status_code: 403, body: body} ->
                data = Jason.decode!(body)
                {:reply, {:error, :denied, data["error"]}, state}
            end
        end

      %Matrix2051.MatrixClient.Client{
        state: :connected,
        local_name: local_name,
        hostname: hostname
      } ->
        {:reply, {:error, {:already_connected, local_name, hostname}}, state}
    end
  end

  @impl true
  def handle_call({:register, local_name, hostname, password}, _from, state) do
    case state do
      %Matrix2051.MatrixClient.Client{
        state: :initial_state,
        irc_mod: irc_mod,
        irc_pid: irc_pid,
        args: args
      } ->
        httpoison = Keyword.get(args, :httpoison, HTTPoison)
        base_url = get_base_url(hostname, httpoison)

        # XXX: This is not part of the Matrix specification;
        # but there is nothing else we can do to support registration.
        # This seems to be only documented here:
        # https://matrix.org/docs/guides/client-server-api/#accounts
        body =
          Jason.encode!(%{
            "auth" => %{type: "m.login.dummy"},
            "username" => local_name,
            "password" => password
          })

        case httpoison.post!(base_url <> "/_matrix/client/r0/register", body) do
          %HTTPoison.Response{status_code: 200, body: body} ->
            data = Jason.decode!(body)

            # TODO: check data["user_id"]
            {_, user_id} = String.split_at(data["user_id"], 1)
            access_token = data["access_token"]

            raw_client = %Matrix2051.Matrix.RawClient{
              base_url: base_url,
              access_token: access_token,
              httpoison: httpoison
            }

            state = %Matrix2051.MatrixClient.Client{
              state: :connected,
              irc_mod: irc_mod,
              irc_pid: irc_pid,
              raw_client: raw_client,
              rooms: Map.new(),
              local_name: local_name,
              hostname: hostname
            }

            poller = irc_mod.matrix_poller(irc_pid)
            send(poller, :connected)

            {:reply, {:ok, user_id}, state}

          %HTTPoison.Response{status_code: 400, body: body} ->
            data = Jason.decode!(body)

            case data do
              %{errcode: "M_USER_IN_USE", error: message} ->
                {:reply, {:error, :user_in_use, message}, state}

              %{errcode: "M_INVALID_USERNAME", error: message} ->
                {:reply, {:error, :invalid_username, message}, state}

              %{errcode: "M_EXCLUSIVE", error: message} ->
                {:reply, {:error, :exclusive, message}, state}
            end

          %HTTPoison.Response{status_code: 403, body: body} ->
            data = Jason.decode!(body)
            {:reply, {:error, :unknown, data["error"]}, state}

          %HTTPoison.Response{status_code: _, body: body} ->
            {:reply, {:error, :unknown, Kernel.inspect(body)}, state}
        end

      %Matrix2051.MatrixClient.Client{
        state: :connected,
        local_name: local_name,
        hostname: hostname
      } ->
        {:reply, {:error, {:already_connected, local_name, hostname}}, state}
    end
  end

  @impl true
  def handle_call({:join_room, room_alias}, _from, state) do
    %Matrix2051.MatrixClient.Client{state: :connected, raw_client: raw_client, rooms: rooms} =
      state

    path = "/_matrix/client/r0/join/" <> URI.encode(room_alias, &URI.char_unreserved?/1)

    room_id = Map.get(rooms, room_alias)

    if room_id != nil do
      {:reply, {:error, :already_joined, room_id}, state}
    else
      case Matrix2051.Matrix.RawClient.post(raw_client, path, "{}") do
        {:ok, %{"room_id" => room_id}} ->
          state = %{state | rooms: Map.put(rooms, room_alias, room_id)}
          {:reply, {:ok, room_id}, state}

        {:error, 403, %{"errcode" => errcode, "error" => message}} ->
          {:reply, {:error, :banned_or_missing_invite, errcode <> ": " <> message}, state}

        {:error, _, %{"errcode" => errcode, "error" => message}} ->
          {:reply, {:error, :unknown, errcode <> ": " <> message}, state}
      end
    end
  end

  defp get_base_url(hostname, httpoison) do
    case httpoison.get!("https://" <> hostname <> "/.well-known/matrix/client") do
      %HTTPoison.Response{status_code: 200, body: body} ->
        data = Jason.decode!(body)
        data["m.homeserver"]["base_url"]

      %HTTPoison.Response{status_code: 404} ->
        "https://" <> hostname

      _ ->
        # The next call will probably fail, but this spares error handling in this one.
        "https://" <> hostname
    end
  end

  def connect(pid, local_name, hostname, password) do
    GenServer.call(pid, {:connect, local_name, hostname, password})
  end

  def raw_client(pid) do
    case GenServer.call(pid, {:dump_state}) do
      %Matrix2051.MatrixClient.Client{
        state: :connected,
        raw_client: raw_client
      } ->
        raw_client

      %Matrix2051.MatrixClient.Client{state: :initial_state} ->
        nil
    end
  end

  def user_id(pid) do
    case GenServer.call(pid, {:dump_state}) do
      %Matrix2051.MatrixClient.Client{
        state: :connected,
        local_name: local_name,
        hostname: hostname
      } ->
        local_name <> ":" <> hostname

      %Matrix2051.MatrixClient.Client{state: :initial_state} ->
        nil
    end
  end

  def register(pid, local_name, hostname, password) do
    GenServer.call(pid, {:register, local_name, hostname, password})
  end

  def join_room(pid, room_alias) do
    GenServer.call(pid, {:join_room, room_alias})
  end
end
