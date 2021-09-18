defmodule Matrix2051.MatrixClient.Client do
  @moduledoc """
    Manages connections to a Matrix homeserver.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(args) do
    {:ok, {:initial_state, args}}
  end

  @impl true
  def handle_call({:dump_state}, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:connect, local_name, hostname, password}, _from, state) do
    case state do
      {:initial_state, {irc_mod, irc_pid, args}} ->
        httpoison = Keyword.get(args, :httpoison, HTTPoison)

        # Get the base URL for this server
        base_url =
          case httpoison.get!("https://" <> hostname <> "/.well-known/matrix/client") do
            %HTTPoison.Response{status_code: 200, body: body} ->
              data = Jason.decode!(body)
              data["m.homeserver"]["base_url"]

            %HTTPoison.Response{status_code: 404} ->
              "https://" <> hostname
          end

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
            {:reply, {:error, :no_password_flow}, state}

          _ ->
            raw_client = %Matrix2051.Matrix.RawClient{base_url: base_url, httpoison: httpoison}

            state =
              {:connected,
               [
                 irc_mod: irc_mod,
                 irc_pid: irc_pid,
                 raw_client: raw_client,
                 local_name: local_name,
                 hostname: hostname
               ]}

            {:reply, {:ok}, state}
        end

      {:connected, {_raw_client, local_name, hostname}} ->
        {:reply, {:error, {:already_connected, local_name, hostname}}, state}
    end
  end

  def connect(pid, local_name, hostname, password) do
    GenServer.call(pid, {:connect, local_name, hostname, password})
  end
end
