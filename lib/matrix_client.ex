defmodule Matrix2051.MatrixClient do
  @moduledoc """
    Manages connections to a Matrix homeserver.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(_args) do
    {:ok, :foo}
  end

  @impl true
  def handle_call({:lookup, new_state}, _from, state) do
    matrix_id = Matrix2051.Config.matrix_id()
    {:reply, {matrix_id, state}, new_state}
  end
end
