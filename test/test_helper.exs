ExUnit.start()
ExUnit.start(timeout: 5000)

Mox.defmock(MockHTTPoison, for: HTTPoison.Base)

defmodule MockIrcSupervisor do
  def matrix_poller(pid) do
    pid
  end

  def state(_pid) do
    :process_ircconn_state
  end

  def matrix_state(_pid) do
    :process_matrix_state
  end

  def writer(_pid) do
    MockIrcConnWriter
  end
end

defmodule MockIrcConnWriter do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(arg, _from, state) do
    {test_pid} = state
    send(test_pid, arg)
    {:reply, :ok, state}
  end
end

defmodule MockMatrixState do
  use Agent

  def start_link(_args) do
    Agent.start_link(fn ->
      %Matrix2051.MatrixClient.State{
        rooms: %{
          "!room_id:example.org" => %Matrix2051.Matrix.RoomState{
            canonical_alias: "#existing_room:example.org",
            members: MapSet.new(["user1:example.org", "user2:example.com"])
          }
        }
      }
    end)
  end
end
