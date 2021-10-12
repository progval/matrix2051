defmodule Matrix2051.IrcConn.State do
  @moduledoc """
    Stores the state of an open IRC connection.
  """
  defstruct [:sup_mod, :sup_pid, :registered, :nick, :gecos, :capabilities]

  use Agent

  def start_link(args) do
    {sup_mod, sup_pid} = args

    Agent.start_link(fn ->
      %Matrix2051.IrcConn.State{
        sup_mod: sup_mod,
        sup_pid: sup_pid,
        registered: false,
        nick: nil,
        gecos: nil,
        capabilities: []
      }
    end)
  end

  def dump_state(pid) do
    Agent.get(pid, fn state -> state end)
  end

  @doc """
    Return {local_name, hostname}. Must be joined with ":" to get the actual nick.
  """
  def nick(pid) do
    Agent.get(pid, fn state -> state.nick end)
  end

  def set_nick(pid, nick) do
    Agent.update(pid, fn state -> %{state | nick: nick} end)
  end

  def registered(pid) do
    Agent.get(pid, fn state -> state.registered end)
  end

  def set_registered(pid) do
    Agent.update(pid, fn state -> %{state | registered: true} end)
  end

  def gecos(pid) do
    Agent.get(pid, fn state -> state.gecos end)
  end

  def set_gecos(pid, gecos) do
    Agent.update(pid, fn state -> %{state | gecos: gecos} end)
  end

  def capabilities(pid) do
    Agent.get(pid, fn state -> state.capabilities end)
  end

  def add_capabilities(pid, new_capabilities) do
    Agent.update(pid, fn state ->
      %{state | capabilities: new_capabilities ++ state.capabilities}
    end)
  end
end
