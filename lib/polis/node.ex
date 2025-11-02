defmodule Polis.Node do
  @moduledoc false

  use GenServer

  alias Polis.PG

  require Logger

  @enforce_keys [:cluster, :group]

  defstruct [
    :cluster,
    :group,
    term: 0,
    voted_for: nil,
    role: :follower,
    election_timer: nil,
    heartbeat_timer: nil,
    voters: MapSet.new(),
    member_snapshot: [],
    election_min: 100,
    election_max: 200,
    heartbeat_ms: 50,
    subscribers: %{}
  ]

  ## ── Public API

  @type server() :: pid() | atom() | {atom(), term()}

  @type option ::
          {:cluster, term()}
          | {:election_min, non_neg_integer()}
          | {:election_max, non_neg_integer()}
          | {:heartbeat_ms, non_neg_integer()}
          | GenServer.option()

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, parse_options!(opts), opts)
  end

  @spec start([option()]) :: GenServer.on_start()
  def start(opts) do
    GenServer.start(__MODULE__, parse_options!(opts), opts)
  end

  @spec leader?(server()) :: boolean()
  def leader?(pid), do: GenServer.call(pid, :leader?)

  @spec role(server()) :: :follower | :candidate | :leader
  def role(pid), do: GenServer.call(pid, :role)

  @spec term(server()) :: non_neg_integer()
  def term(pid), do: GenServer.call(pid, :term)

  @spec members(server()) :: [pid()]
  def members(pid), do: GenServer.call(pid, :members)

  @spec current_leader(server(), non_neg_integer()) :: pid() | nil
  def current_leader(pid, timeout \\ 200) do
    GenServer.call(pid, :current_leader, timeout)
  end

  @spec subscribe(server(), pid()) :: :ok
  def subscribe(pid, subscriber \\ self()) do
    GenServer.cast(pid, {:subscribe, subscriber})
  end

  @spec unsubscribe(server(), pid()) :: :ok
  def unsubscribe(pid, subscriber \\ self()) do
    GenServer.cast(pid, {:unsubscribe, subscriber})
  end

  ## ── GenServer Callbacks

  @impl true
  def init(opts) do
    group = {:polis, opts.cluster}
    :ok = PG.join(group, self())

    {:ok,
     become_follower(%__MODULE__{
       cluster: opts.cluster,
       group: group,
       election_min: opts[:election_min] || 100,
       election_max: opts[:election_max] || 200,
       heartbeat_ms: opts[:heartbeat_ms] || 50
     })}
  end

  @impl true
  def handle_call(:leader?, _from, %__MODULE__{role: :leader} = s), do: {:reply, true, s}
  def handle_call(:leader?, _from, s), do: {:reply, false, s}
  def handle_call(:role, _from, s), do: {:reply, s.role, s}
  def handle_call(:term, _from, s), do: {:reply, s.term, s}
  def handle_call(:members, _from, s), do: {:reply, get_members(s), s}

  def handle_call(:current_leader, _from, %__MODULE__{role: :leader} = s),
    do: {:reply, self(), s}

  def handle_call(:current_leader, _from, s),
    do: {:reply, get_members(s) |> Enum.find(&safe_call(&1, :leader?)), s}

  @impl true
  def handle_cast({:subscribe, subscriber}, s) do
    subscribers =
      Map.put_new_lazy(s.subscribers, subscriber, fn ->
        Process.monitor(subscriber)
      end)

    {:noreply, %{s | subscribers: subscribers}}
  end

  def handle_cast({:unsubscribe, subscriber}, s) do
    {ref, subscribers} = Map.pop(s.subscribers, subscriber)
    if ref, do: Process.demonitor(ref)
    {:noreply, %{s | subscribers: subscribers}}
  end

  @impl true
  def handle_info(:election_timeout, %__MODULE__{role: :follower} = s),
    do: {:noreply, become_candidate(s) |> request_votes_from_peers()}

  def handle_info(:election_timeout, %__MODULE__{role: :candidate} = s) do
    case become_leader_if_majority(s) do
      %__MODULE__{role: :leader} = s -> {:noreply, s}
      s -> {:noreply, step_down(s, s.term + 1)}
    end
  end

  def handle_info(:election_timeout, s),
    do: {:noreply, s}

  def handle_info(:heartbeat_tick, %__MODULE__{role: :leader} = s),
    do: {:noreply, send_append_entries(s) |> schedule_heartbeat()}

  def handle_info(:heartbeat_tick, s), do: {:noreply, s}

  def handle_info({:request_vote, from_pid, term, _candidate_id}, s)
      when term > s.term, do: {:noreply, step_down(s, term) |> maybe_vote(from_pid)}

  def handle_info({:request_vote, _from_pid, term, _candidate_id}, s)
      when term < s.term, do: {:noreply, s}

  def handle_info({:request_vote, from_pid, _term, _candidate_id}, s),
    do: {:noreply, maybe_vote(s, from_pid)}

  def handle_info({:request_vote_reply, _from, term, _granted}, s)
      when term > s.term, do: {:noreply, step_down(s, term)}

  def handle_info({:request_vote_reply, _from, term, _granted}, s)
      when term < s.term, do: {:noreply, s}

  def handle_info({:request_vote_reply, from, _term, true}, %__MODULE__{role: :candidate} = s),
    do: {:noreply, accept_vote(s, from) |> become_leader_if_majority()}

  def handle_info({:request_vote_reply, _from, _term, _granted}, s),
    do: {:noreply, s}

  def handle_info({:append_entries, from_pid, term}, s)
      when term >= s.term do
    s = s |> step_down(term) |> reset_election_timer()
    send(from_pid, {:append_entries_reply, self(), s.term})
    {:noreply, s}
  end

  def handle_info({:append_entries, from_pid, _term}, s) do
    send(from_pid, {:append_entries_reply, self(), s.term})
    {:noreply, s}
  end

  def handle_info({:append_entries_reply, _from, _term}, s) do
    {:noreply, s}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, s) do
    {:noreply,
     %{
       s
       | subscribers: Map.delete(s.subscribers, pid),
         member_snapshot: List.delete(s.member_snapshot, pid)
     }}
  end

  @impl true
  def terminate(_reason, s) do
    s = cancel_heartbeat(s) |> cancel_election_timer()
    PG.leave(s.group, self())
    :ok
  end

  ## ── Internal functions

  defp parse_options!(opts) do
    cluster = Keyword.fetch!(opts, :cluster)

    Enum.reduce(opts, %{cluster: cluster}, fn
      {:election_min, v}, s when is_integer(v) and v > 0 -> Map.put(s, :election_min, v)
      {:election_max, v}, s when is_integer(v) and v > 0 -> Map.put(s, :election_max, v)
      {:heartbeat_ms, v}, s when is_integer(v) and v > 0 -> Map.put(s, :heartbeat_ms, v)
      _, s -> s
    end)
  end

  defp get_members(s) do
    PG.get_members(s.group)
    |> Enum.filter(fn pid -> pid != self() end)
  end

  defp reset_election_timer(s) do
    s = cancel_election_timer(s)
    t = s.election_min + :rand.uniform(s.election_max - s.election_min)
    ref = Process.send_after(self(), :election_timeout, t)
    %{s | election_timer: ref}
  end

  defp schedule_heartbeat(s) do
    s = cancel_heartbeat(s)
    ref = Process.send_after(self(), :heartbeat_tick, s.heartbeat_ms)
    %{s | heartbeat_timer: ref}
  end

  defp step_down(s, new_term) do
    %{become_follower(s) | term: new_term}
  end

  defp cancel_heartbeat(s) do
    if s.heartbeat_timer, do: Process.cancel_timer(s.heartbeat_timer)
    %{s | heartbeat_timer: nil}
  end

  defp become_follower(s) do
    %{s | role: :follower, voted_for: nil, voters: MapSet.new(), member_snapshot: []}
    |> cancel_heartbeat()
    |> reset_election_timer()
    |> notify_if_role_change(s.role)
  end

  defp become_candidate(%__MODULE__{role: :follower} = s) do
    %{
      s
      | role: :candidate,
        term: s.term + 1,
        voted_for: self(),
        voters: MapSet.new([self()]),
        member_snapshot: get_members(s)
    }
    |> monitor_snapshot_members()
    |> reset_election_timer()
    |> notify_if_role_change(s.role)
  end

  defp monitor_snapshot_members(s) do
    Enum.each(s.member_snapshot, &Process.monitor/1)
    s
  end

  defp become_leader(%__MODULE__{role: :candidate} = s) do
    %{s | role: :leader, voted_for: nil, voters: MapSet.new(), member_snapshot: []}
    |> cancel_election_timer()
    |> schedule_heartbeat()
    |> send_append_entries()
    |> notify_if_role_change(s.role)
  end

  defp become_leader_if_majority(%__MODULE__{role: :candidate} = s) do
    total = length(s.member_snapshot) + 1
    majority = div(total, 2) + 1
    if MapSet.size(s.voters) >= majority, do: become_leader(s), else: s
  end

  defp cancel_election_timer(s) do
    if s.election_timer, do: Process.cancel_timer(s.election_timer)
    %{s | election_timer: nil}
  end

  defp request_votes_from_peers(%__MODULE__{role: :candidate} = s) do
    Enum.each(s.member_snapshot, &send(&1, {:request_vote, self(), s.term, self()}))

    s
  end

  defp send_append_entries(%__MODULE__{role: :leader} = s) do
    get_members(s)
    |> Enum.each(&send(&1, {:append_entries, self(), s.term}))

    s
  end

  defp maybe_vote(s, from_pid) when is_nil(s.voted_for) do
    send(from_pid, {:request_vote_reply, self(), s.term, true})

    %{s | voted_for: from_pid} |> reset_election_timer()
  end

  defp maybe_vote(s, _from_pid), do: s

  defp accept_vote(s, from_pid) do
    %{s | voters: MapSet.put(s.voters, from_pid)}
  end

  defp notify_if_role_change(s, old_role) when s.role === old_role, do: s

  defp notify_if_role_change(s, _old_role) do
    Enum.each(s.subscribers, fn {subscriber, _ref} ->
      send(subscriber, {:polis_role_changed, self(), s.role})
    end)

    s
  end

  defp safe_call(pid, msg) do
    try do
      GenServer.call(pid, msg, 100)
    catch
      :exit, _ -> false
    end
  end
end
