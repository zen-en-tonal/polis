## Polis

Lightweight Raft-style leader election and cluster membership for Elixir processes, built on top of Erlang/OTP's `:pg`.

Polis lets you spin up multiple processes in a group (a "cluster") and ensures they converge to exactly one leader, handle re-elections, and provide simple introspection APIs. It focuses on leader election, heartbeats, and membership — not log replication — making it a small, embeddable building block for coordination tasks.

### Status

- Version: 0.0.1
- Elixir: ~> 1.12 (OTP 24+ recommended)
- Scope: Leader election and membership only (no log replication/persistence yet)


## Features

- Simple process group membership via `:pg`
- Raft-inspired leader election with randomized timeouts
- Heartbeats from the leader to followers
- Query APIs: `leader?/1`, `role/1`, `term/1`, `members/1`, `current_leader/2`
- Pub/sub for role changes via `subscribe/2` and `unsubscribe/2`
- Property-based tests with StreamData validating convergence and resilience


## Installation

This library is not published on Hex as of now. Add it as a Git dependency in your project:

```elixir
def deps do
  [
    {:polis, git: "https://github.com/zen-en-tonal/polis", tag: "v0.0.1"}
  ]
end
```

When used as a dependency, the `Polis.Application` supervisor will start a dedicated `:pg` instance automatically.


## Quick start

Open an IEx session and create a small cluster of processes in the same BEAM node:

```elixir
{:ok, a} = Polis.start_link(cluster: :demo)
{:ok, b} = Polis.start_link(cluster: :demo)
{:ok, c} = Polis.start_link(cluster: :demo)

# give the cluster time to elect a leader
Process.sleep(200)

Polis.leader?(a)         #=> true | false
Polis.role(b)            #=> :follower | :candidate | :leader
Polis.term(c)            #=> non_neg_integer()
Polis.members(a)         #=> [pid(), ...] (other peers, excludes self)
Polis.current_leader(b)  #=> pid() | nil
```

Subscribe to role-change notifications:

```elixir
Polis.subscribe(a)  # subscriber defaults to the calling process

receive do
  {:polis_role_changed, node_pid, new_role} ->
    IO.inspect({:changed, node_pid, new_role})
after 1_000 ->
  :noop
end
```


## Configuration

Each node accepts election and heartbeat tuning options:

- `:cluster` (required) – any term identifying your process group, e.g. `:demo` or `{:my, :cluster}`
- `:election_min` – min election timeout in ms (default 100)
- `:election_max` – max election timeout in ms (default 200)
- `:heartbeat_ms` – heartbeat interval in ms (default 50)

Example:

```elixir
{:ok, pid} = Polis.start_link(
  cluster: :demo,
  election_min: 50,
  election_max: 100,
  heartbeat_ms: 20
)
```


## Design notes and limitations

- In-scope: leader election, membership, heartbeats, and role-change notifications.
- Out-of-scope (for now): replicated log, persistence, client commands, and cluster reconfiguration protocols.
- `:pg` supports distributed Erlang; if your BEAM nodes are connected, groups can span nodes. This library does not ship its own distribution wiring.
- Members tracked by `members/1` exclude the caller process; use `self()` alongside `members/1` if you need the full set.


## Development

Install dependencies and run the test suite:

```bash
mix deps.get
mix test
```

Property-based tests are tagged; to focus on them:

```bash
mix test --only property
```

Static analysis and types:

```bash
# Lint
mix credo --strict

# Dialyzer (first run will build PLTs)
mix dialyzer
```

Generate docs:

```bash
mix docs
```


## API overview

Public functions (from `Polis` facade):

- `start_link/1` – start a node linked to the caller
- `start/1` – start a node without linking
- `leader?/1` – is this node currently the leader?
- `role/1` – one of `:follower | :candidate | :leader`
- `term/1` – current term number
- `members/1` – other node PIDs in the same cluster
- `current_leader/2` – returns the current leader PID (or `nil`), with optional timeout
- `subscribe/2` – subscribe a pid to `{:polis_role_changed, pid, role}` messages
- `unsubscribe/2` – remove a subscription


## Examples

Start N nodes, assert convergence to exactly one leader:

```elixir
cluster = make_ref()
nodes = for _ <- 1..5, do: elem(Polis.start_link(cluster: cluster), 1)
Process.sleep(300)

leaders = Enum.count(nodes, &Polis.leader?/1)
IO.inspect(leaders, label: "leaders")   # should be 1
```

Handle leader failover:

```elixir
leader = Enum.find(nodes, &Polis.leader?/1)
GenServer.stop(leader, :normal)
Process.sleep(300)
new_leader = Enum.find(nodes, &Process.alive?/1) |> then(&Polis.current_leader(&1))
```

## License

MIT

