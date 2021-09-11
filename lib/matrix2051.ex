defmodule Matrix2051 do
  @moduledoc """
    Main module of Matrix2051.
  """
  use Application

  @doc """
    Entrypoint. Takes the global config as args, and starts Matrix2051.Supervisor
  """
  @impl true
  def start(_type, args) do
    children = [
      {Matrix2051.Supervisor, args}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
