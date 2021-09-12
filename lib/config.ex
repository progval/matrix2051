defmodule Matrix2051.Config do
  @moduledoc """
    Global configuration.
  """
  use Agent

  def start_link(args) do
    Agent.start_link(fn -> args end, name: __MODULE__)
  end

  def matrix_id() do
    Agent.get(__MODULE__, & &1[:matrix_id])
  end

  def port() do
    2051
  end
end
