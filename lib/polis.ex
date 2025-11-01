defmodule Polis do
  @moduledoc """
  Polis is a lightweight Elixir library that implements the Raft consensus algorithm,
  for leader election and cluster membership management.

  ## Getting Started

  To start a Polis node, use the `start_link/1` or `start/1` functions with the required options.

      {:ok, pid} = Polis.start_link(cluster: :my_cluster)

  """

  @type server() :: pid() | atom() | {atom(), term()}

  @type option ::
          {:cluster, term()}
          | {:election_min, non_neg_integer()}
          | {:election_max, non_neg_integer()}
          | {:heartbeat_ms, non_neg_integer()}
          | GenServer.option()

  @doc """
  Starts a Polis node with linking.

  ## Options

    - `:cluster` - (required) The cluster identifier.
    - `:election_min` - Minimum election timeout in milliseconds. Default is `100`.
    - `:election_max` - Maximum election timeout in milliseconds. Default is `200`.
    - `:heartbeat_ms` - Heartbeat interval in milliseconds. Default is `50`.
    - Other `GenServer` options.

  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts), do: Polis.Node.start_link(opts)

  @doc """
  Starts a Polis node without linking.
  See `start_link/1` for options.
  """
  @spec start([option()]) :: GenServer.on_start()
  def start(opts), do: Polis.Node.start(opts)

  @doc """
  Returns `true` if the node is the current leader, `false` otherwise.
  """
  @spec leader?(server()) :: boolean()
  def leader?(pid), do: Polis.Node.leader?(pid)

  @doc """
  Returns the current role of the node: `:follower`, `:candidate`, or `:leader`.
  """
  @spec role(server()) :: :follower | :candidate | :leader
  def role(pid), do: Polis.Node.role(pid)

  @doc """
  Returns the current term of the node.
  """
  @spec term(server()) :: non_neg_integer()
  def term(pid), do: Polis.Node.term(pid)

  @doc """
  Returns the list of member PIDs in the cluster.

  The members are not included itself.
  """
  @spec members(server()) :: [pid()]
  def members(pid), do: Polis.Node.members(pid)

  @doc """
  Returns the PID of the current leader, or `nil` if there is no leader.
  """
  @spec current_leader(server(), non_neg_integer()) :: pid() | nil
  def current_leader(pid, timeout \\ 200), do: Polis.Node.current_leader(pid, timeout)

  @doc """
  Subscribes the given `subscriber` to receive node state change notifications.

  Subscriptions will receive messages in the form:

      {:polis_role_changed, node_pid, new_role}

  If no `subscriber` is provided, the calling process is used.
  """
  @spec subscribe(server(), pid()) :: :ok
  def subscribe(pid, subscriber \\ self()), do: Polis.Node.subscribe(pid, subscriber)

  @doc """
  Unsubscribes the given `subscriber_pid` from receiving node state change notifications.

  If no `subscriber` is provided, the calling process is used.
  """
  @spec unsubscribe(server(), pid()) :: :ok
  def unsubscribe(pid, subscriber \\ self()), do: Polis.Node.unsubscribe(pid, subscriber)
end
