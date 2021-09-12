defmodule Matrix2051.IrcConn.State do
  @moduledoc """
    Stores the state of an open IRC connection.
  """
  defstruct [:sup_mod, :sup_pid, :registered, :gecos, :caps]

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    {sup_mod, sup_pid} = args

    {:ok,
     %Matrix2051.IrcConn.State{
       sup_mod: sup_mod,
       sup_pid: sup_pid,
       registered: false,
       gecos: nil,
       caps: []
     }}
  end

  def handle_call({:get, name}, _from, state) do
    {:reply, Map.get(state, name), state}
  end

  def handle_call({:set, name, value}, _from, state) do
    {:reply, value, Map.put(state, name, value)}
  end

  def handle_call({:dump_state}, _from, state) do
    {:reply, state, state}
  end

  def dump_state(pid) do
    GenServer.call(pid, {:dump_state})
  end

  def nick(_pid) do
    # No other nick is allowed.
    Matrix2051.Config.matrix_id()
  end

  def registered(pid) do
    GenServer.call(pid, {:get, :registered})
  end

  def set_registered(pid) do
    GenServer.call(pid, {:set, :registered, true})
  end

  def gecos(pid) do
    GenServer.call(pid, {:get, :gecos})
  end

  def set_gecos(pid, gecos) do
    GenServer.call(pid, {:set, :gecos, gecos})
  end
end
