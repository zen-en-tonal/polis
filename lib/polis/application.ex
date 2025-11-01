defmodule Polis.Application do
  @moduledoc false

  use Application

  alias Polis.PG

  @impl true
  def start(_type, _args) do
    children = [
      PG.child_spec()
    ]

    opts = [strategy: :one_for_one, name: Polis.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
