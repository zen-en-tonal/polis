defmodule Polis.PG do
  @moduledoc false

  def start_link() do
    :pg.start_link(__MODULE__)
  end

  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def join(group, pid) do
    :pg.join(__MODULE__, group, pid)
  end

  def leave(group, pid) do
    :pg.leave(__MODULE__, group, pid)
  end

  def get_members(group) do
    :pg.get_members(__MODULE__, group)
  end
end
