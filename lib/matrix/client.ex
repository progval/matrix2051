defmodule Matrix2051.MatrixClient do
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
    matrix_id = Matrix2051.Config.matrix_id()
    {:reply, state, state}
  end

  defp initialize_state(state) do
    case state do
      {:initial_state, args} ->
        httpoison = Keyword.get(args, :httpoison, HTTPoison)
        matrix_id = Matrix2051.Config.matrix_id()
        [local_name, host_name] = String.split(matrix_id, ~r/:/, parts: 2)

        # Get the base URL for this server
        base_url =
          case httpoison.get!("https://" <> host_name <> "/.well-known/matrix/client") do
            %HTTPoison.Response{status_code: 200, body: body} ->
              data = Jason.decode!(body)
              data["m.homeserver"]["base_url"]

            %HTTPoison.Response{status_code: 404} ->
              "https://" <> host_name
          end

        {httpoison, matrix_id, base_url}

      _ ->
        state
    end
  end
end
