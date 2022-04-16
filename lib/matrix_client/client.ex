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

defmodule M51.MatrixClient.Client do
  @moduledoc """
    Manages connections to a Matrix homeserver.
  """
  use GenServer

  require Logger

  # The state of this client
  defstruct [
    # :initial_state or :connected
    :state,
    # extra keyword list passed to init/1
    :args,
    # pid of IrcConnSupervisor
    :irc_pid,
    # M51.Matrix.RawClient structure
    :raw_client,
    :local_name,
    :hostname
  ]

  # timeout used for all requests sent to a homeserver.
  # It should be slightly larger than M51.Matrix.RawClient's timeout,
  @timeout 25000

  def start_link(opts) do
    {sup_pid, _extra_args} = opts

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {M51.Registry, {sup_pid, :matrix_client}}}
    )
  end

  @impl true
  def init(args) do
    {irc_pid, extra_args} = args

    {:ok,
     %M51.MatrixClient.Client{
       state: :initial_state,
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
      %M51.MatrixClient.Client{
        state: :initial_state,
        irc_pid: irc_pid
      } ->
        httpoison = M51.Config.httpoison()
        base_url = get_base_url(hostname)

        # Check the server supports password login
        url = base_url <> "/_matrix/client/r0/login"
        Logger.debug("(raw) GET #{url}")
        response = httpoison.get!(url)
        Logger.debug(Kernel.inspect(response))

        case response do
          %HTTPoison.Response{status_code: 200, body: body} ->
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

                url = base_url <> "/_matrix/client/r0/login"
                Logger.debug("(raw) POST #{url} " <> Kernel.inspect(body))
                response = httpoison.post!(url, body)
                Logger.debug(Kernel.inspect(response))

                case response do
                  %HTTPoison.Response{status_code: 200, body: body} ->
                    data = Jason.decode!(body)

                    if data["user_id"] != "@" <> local_name <> ":" <> hostname do
                      raise "Unexpected user_id: " <> data["user_id"]
                    end

                    access_token = data["access_token"]

                    raw_client = %M51.Matrix.RawClient{
                      base_url: base_url,
                      access_token: access_token,
                      httpoison: httpoison
                    }

                    state = %M51.MatrixClient.Client{
                      state: :connected,
                      irc_pid: irc_pid,
                      raw_client: raw_client,
                      local_name: local_name,
                      hostname: hostname
                    }

                    Registry.send({M51.Registry, {irc_pid, :matrix_poller}}, :connected)

                    {:reply, {:ok}, state}

                  %HTTPoison.Response{status_code: 403, body: body} ->
                    data = Jason.decode!(body)
                    {:reply, {:error, :denied, data["error"]}, state}
                end
            end

          %HTTPoison.Response{status_code: status_code} ->
            message =
              "Could not reach the Matrix homeserver for #{hostname}, #{url} returned HTTP #{
                status_code
              }. Make sure this is a Matrix homeserver and https://#{hostname}/.well-known/matrix/client is properly configured."

            {:reply, {:error, :unknown, message}, state}
        end

      %M51.MatrixClient.Client{
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
      %M51.MatrixClient.Client{
        state: :initial_state,
        irc_pid: irc_pid
      } ->
        httpoison = M51.Config.httpoison()
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

            raw_client = %M51.Matrix.RawClient{
              base_url: base_url,
              access_token: access_token,
              httpoison: httpoison
            }

            state = %M51.MatrixClient.Client{
              state: :connected,
              irc_pid: irc_pid,
              raw_client: raw_client,
              local_name: local_name,
              hostname: hostname
            }

            Registry.send({M51.Registry, {irc_pid, :matrix_poller}}, :connected)

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

      %M51.MatrixClient.Client{
        state: :connected,
        local_name: local_name,
        hostname: hostname
      } ->
        {:reply, {:error, {:already_connected, local_name, hostname}}, state}
    end
  end

  @impl true
  def handle_call({:join_room, room_alias}, _from, state) do
    %M51.MatrixClient.Client{state: :connected, raw_client: raw_client, irc_pid: irc_pid} = state

    matrix_state = M51.IrcConn.Supervisor.matrix_state(irc_pid)

    path = "/_matrix/client/r0/join/" <> urlquote(room_alias)

    case M51.MatrixClient.State.room_from_irc_channel(matrix_state, room_alias) do
      {room_id, _room} ->
        {:reply, {:error, :already_joined, room_id}, state}

      nil ->
        case M51.Matrix.RawClient.post(raw_client, path, "{}") do
          {:ok, %{"room_id" => room_id}} ->
            {:reply, {:ok, room_id}, state}

          {:error, 403, %{"errcode" => errcode, "error" => message}} ->
            {:reply, {:error, :banned_or_missing_invite, errcode <> ": " <> message}, state}

          {:error, _, %{"errcode" => errcode, "error" => message}} ->
            {:reply, {:error, :unknown, errcode <> ": " <> message}, state}

          {:error, nil, error} ->
            {:reply, {:error, :unknown, Kernel.inspect(error)}, state}
        end
    end
  end

  @impl true
  def handle_call({:send_event, channel, event_type, label, event}, _from, state) do
    %M51.MatrixClient.Client{
      state: :connected,
      irc_pid: irc_pid
    } = state

    matrix_state = M51.IrcConn.Supervisor.matrix_state(irc_pid)

    transaction_id = label_to_transaction_id(label)

    case M51.MatrixClient.State.room_from_irc_channel(matrix_state, channel) do
      nil ->
        {:reply, {:error, {:room_not_found, channel}}, state}

      {room_id, _room} ->
        M51.MatrixClient.Sender.queue_event(
          irc_pid,
          room_id,
          event_type,
          transaction_id,
          event
        )

        {:reply, {:ok, {transaction_id}}, state}
    end
  end

  @impl true
  def handle_call({:get_event_context, channel, event_id, limit}, _from, state) do
    %M51.MatrixClient.Client{
      state: :connected,
      irc_pid: irc_pid,
      raw_client: raw_client
    } = state

    matrix_state = M51.IrcConn.Supervisor.matrix_state(irc_pid)

    reply =
      case M51.MatrixClient.State.room_from_irc_channel(matrix_state, channel) do
        nil ->
          {:error, {:room_not_found, channel}}

        {room_id, _room} ->
          path =
            "/_matrix/client/r0/rooms/#{urlquote(room_id)}/context/#{urlquote(event_id)}?" <>
              URI.encode_query(%{"limit" => limit})

          case M51.Matrix.RawClient.get(raw_client, path) do
            {:ok, events} -> {:ok, events}
            {:error, error} -> {:error, error}
          end
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:is_valid_alias, room_id, room_alias}, _from, state) do
    %M51.MatrixClient.Client{
      raw_client: raw_client
    } = state

    path = "/_matrix/client/r0/directory/room/#{urlquote(room_alias)}"

    case M51.Matrix.RawClient.get(raw_client, path) do
      {:ok, event} ->
        if Map.get(event, "room_id") == room_id do
          {:reply, true, state}
        else
          {:reply, false, state}
        end

      {:error, 404, _} ->
        {:reply, false, state}

      {:error, _, _} ->
        # TODO: retry
        {:reply, false, state}
    end
  end

  @doc """
    Generates a unique transaction id, assuming the 'label' is either a unique string,
    or 'nil'.

    'transaction_id_to_label' is the inverse of this function.

    # Examples

        iex> M51.MatrixClient.Client.label_to_transaction_id("foo")
        "m51-cl-Zm9v"
        iex> M51.MatrixClient.Client.label_to_transaction_id("foo")
        "m51-cl-Zm9v"
        iex> txid1 = M51.MatrixClient.Client.label_to_transaction_id(nil)
        iex> txid2 = M51.MatrixClient.Client.label_to_transaction_id(nil)
        iex> txid1 == txid2
        false
        iex> M51.MatrixClient.Client.transaction_id_to_label(
        ...>   M51.MatrixClient.Client.label_to_transaction_id("foo")
        ...> )
        "foo"
        iex> M51.MatrixClient.Client.transaction_id_to_label(txid1)
        nil
  """
  def label_to_transaction_id(label) do
    case label do
      nil -> "m51-gen-" <> Base.url_encode64(:crypto.strong_rand_bytes(64))
      # URI.encode() may be shorter
      label -> "m51-cl-" <> Base.url_encode64(label)
    end
  end

  @doc """
    Inverse function of 'label_to_transaction_id': recomputes the original label if any,
    or returns nil.

    # Examples

        iex> M51.MatrixClient.Client.transaction_id_to_label("m51-cl-Zm9v")
        "foo"
        iex> M51.MatrixClient.Client.transaction_id_to_label("m51-gen-AAAA")
        nil
        iex> M51.MatrixClient.Client.transaction_id_to_label(
        ...>   M51.MatrixClient.Client.label_to_transaction_id("foo")
        ...> )
        "foo"
        iex> M51.MatrixClient.Client.transaction_id_to_label(
        ...>   M51.MatrixClient.Client.label_to_transaction_id(nil)
        ...> )
        nil
  """
  def transaction_id_to_label(transaction_id) do
    captures = Regex.named_captures(~r/m51-cl-(?<label>.*)/, transaction_id)

    case captures do
      %{"label" => label} -> Base.url_decode64!(label)
      nil -> nil
    end
  end

  def get_base_url(hostname, httpoison \\ nil) do
    httpoison =
      case httpoison do
        nil -> M51.Config.httpoison()
        httpoison -> httpoison
      end

    wellknown_url = "https://" <> hostname <> "/.well-known/matrix/client"

    case httpoison.get!(wellknown_url) do
      %HTTPoison.Response{status_code: 200, body: body} ->
        data = Jason.decode!(body)
        base_url = data["m.homeserver"]["base_url"]
        Logger.debug("Well-known request for #{wellknown_url} yielded #{base_url}")
        base_url

      %HTTPoison.Response{status_code: 404} ->
        base_url = "https://" <> hostname

        Logger.debug(
          "Well-known request for #{wellknown_url} returned 404 error. " <>
            "Assuming #{base_url} as base URL"
        )

        base_url

      res ->
        # The next call will probably fail, but this spares error handling in this one.
        base_url = "https://" <> hostname

        Logger.warn(
          "Well-known request for #{wellknown_url} returned #{Kernel.inspect(res)}. " <>
            "Falling back to #{base_url}"
        )

        base_url
    end
  end

  def connect(pid, local_name, hostname, password) do
    GenServer.call(pid, {:connect, local_name, hostname, password}, @timeout)
  end

  def raw_client(pid) do
    case GenServer.call(pid, {:dump_state}) do
      %M51.MatrixClient.Client{
        state: :connected,
        raw_client: raw_client
      } ->
        raw_client

      %M51.MatrixClient.Client{state: :initial_state} ->
        nil
    end
  end

  def user_id(pid) do
    case GenServer.call(pid, {:dump_state}) do
      %M51.MatrixClient.Client{
        state: :connected,
        local_name: local_name,
        hostname: hostname
      } ->
        local_name <> ":" <> hostname

      %M51.MatrixClient.Client{state: :initial_state} ->
        nil
    end
  end

  def register(pid, local_name, hostname, password) do
    GenServer.call(pid, {:register, local_name, hostname, password}, @timeout)
  end

  def join_room(pid, room_alias) do
    GenServer.call(pid, {:join_room, room_alias}, @timeout)
  end

  @doc """
    Sends the given event object.

    If 'label' is not nil, it will be passed as a 'label' message tagt when
    the event is seen in the event stream.
  """
  def send_event(pid, channel, label, event_type, event) do
    GenServer.call(pid, {:send_event, channel, event_type, label, event}, @timeout)
  end

  @doc """
    Returns events that happened just before or after the specified event_id.

    https://matrix.org/docs/spec/client_server/r0.6.1#id131
  """
  def get_event_context(pid, channel, event_id, limit) do
    GenServer.call(pid, {:get_event_context, channel, event_id, limit}, @timeout)
  end

  defp urlquote(s) do
    URI.encode(s, &URI.char_unreserved?/1)
  end

  def valid_alias?(pid, room_id, room_alias) do
    GenServer.call(pid, {:is_valid_alias, room_id, room_alias})
  end
end
