defmodule Matrix2051.Matrix.Client do
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
    state = initialize_state(state)
    {:reply, state, state}
  end

  defp initialize_state({:initial_state, args}) do
    httpoison = Keyword.get(args, :httpoison, HTTPoison)
    local_name = args[:local_name]
    hostname = args[:hostname]

    # Get the base URL for this server
    base_url =
      case httpoison.get!("https://" <> hostname <> "/.well-known/matrix/client") do
        %HTTPoison.Response{status_code: 200, body: body} ->
          data = Jason.decode!(body)
          data["m.homeserver"]["base_url"]

        %HTTPoison.Response{status_code: 404} ->
          "https://" <> hostname
      end

    raw_client = %Matrix2051.Matrix.RawClient{base_url: base_url, httpoison: httpoison}

    {:state, {raw_client, local_name, hostname}}
  end

  defp initialize_state({:state, state}) do
    state
  end
end
