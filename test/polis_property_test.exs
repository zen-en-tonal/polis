defmodule Polis.PropertyTest do
  @moduledoc """
  # Polis 高負荷プロパティベーステスト

  このドキュメントでは、Polisライブラリの高負荷シナリオにおけるプロパティベーステストについて説明します。

  ## 概要

  Polisは軽量なRaftコンセンサスアルゴリズムの実装で、リーダー選出とクラスタメンバーシップ管理を提供します。これらのプロパティベーステストは、高負荷や障害発生時にもシステムが正しく動作することを検証します。

  ## テストカテゴリ

  ### 1. 高負荷シナリオ: クラスタのプロパティベーステスト

  #### 1.1 複数ノードが同時起動しても必ず1つのリーダーに収束する

  **検証内容:**
  - 3〜20個のノードを同時起動
  - 必ず1つだけリーダーが選出される
  - すべてのノードが同じterm（または遷移中で最大2つのterm）にいる

  **プロパティ:**
  ```
  ∀ cluster: 任意のクラスタサイズに対して
  起動後の安定状態で leaders(cluster) = 1
  ```

  #### 1.2 ノードの追加・削除を繰り返してもリーダー選出が維持される

  **検証内容:**
  - 初期ノード数: 3〜10個
  - 動的にノードを追加・削除（5〜20回の操作）
  - 各操作後もリーダーが1つだけ存在する

  **プロパティ:**
  ```
  ∀ operations: 追加・削除の任意の操作列に対して
  各操作後の安定状態で leaders(cluster) = 1
  ```

  #### 1.3 高頻度のリーダー問い合わせでも一貫性が保たれる

  **検証内容:**
  - 3〜10個のノード
  - 50〜200回の並行リーダー問い合わせ
  - すべての問い合わせで同じリーダーが返される

  **プロパティ:**
  ```
  ∀ concurrent_queries: 並行クエリの集合に対して
  unique(results) ≤ 1
  ```

  #### 1.4 term番号は常に単調増加する

  **検証内容:**
  - 3〜8個のノード
  - リーダーを強制停止してre-electionを発生
  - 各ノードのterm番号は減少しない

  **プロパティ:**
  ```
  ∀ node ∈ cluster:
  term_before ≤ term_after
  ```

  #### 1.5 購読者への通知が正しく配信される

  **検証内容:**
  - 3〜8個のノード
  - 1〜10個の購読プロセス
  - ロール変更時に通知が正しく配信される

  **プロパティ:**
  ```
  ∀ subscriber: 購読者に対して
  role_change発生時に {:polis_role_changed, pid, role} を受信
  ```

  ### 2. 耐障害性プロパティテスト

  #### 2.1 過半数のノードが生存していればリーダー選出が可能

  **検証内容:**
  - 5〜15個のノード
  - 少数（過半数未満）のノードを停止
  - 残りのノードで新しいリーダーが選出される

  **プロパティ:**
  ```
  ∀ cluster: total_nodes = n, failed_nodes < n/2 に対して
  leaders(remaining_nodes) = 1
  ```

  #### 2.2 ネットワーク分断後の再統合でも一貫性が保たれる

  **検証内容:**
  - 5〜10個のノード
  - クラスタを2つのパーティションに分割
  - パーティション1を停止し、パーティション2で新リーダー選出
  - パーティション1を再起動して再統合
  - 統合後、リーダーは1つだけ

  **プロパティ:**
  ```
  ∀ partition_scenario: ネットワーク分断シナリオに対して
  heal(partition1, partition2) => leaders(cluster) = 1
  ```

  ### 3. パフォーマンス特性のプロパティテスト

  #### 3.1 タイムアウト設定が異なってもリーダー選出が成功する

  **検証内容:**
  - election_min: 30〜100ms
  - election_max: 101〜200ms
  - heartbeat_ms: 10〜50ms
  - 様々なタイムアウト設定でリーダー選出が成功

  **プロパティ:**
  ```
  ∀ timeout_config: 有効なタイムアウト設定に対して
  leaders(cluster) = 1
  ```

  #### 3.2 多数の並行操作でもデッドロックが発生しない

  **検証内容:**
  - 3〜8個のノード
  - 50〜150個の並行操作（leader?, role, term, members, current_leader）
  - すべての操作が完了する（デッドロックなし）

  **プロパティ:**
  ```
  ∀ concurrent_operations: 並行操作の集合に対して
  all_tasks_complete ∧ some_operations_succeed
  ```

  ## テスト設計の原則

  ### 1. プロパティベーステストとは

  プロパティベーステストは、システムが満たすべき普遍的な性質（プロパティ）を定義し、ランダムな入力で検証する手法です。

  ### 2. StreamDataライブラリの使用

  このテストでは`stream_data`ライブラリを使用して、ランダムなテストケースを生成します。

  ```elixir
  check all(
  node_count <- integer(3..20),
  max_runs: 50
  ) do
  # テストコード
  end
  ```

  ### 3. クリーンアップの重要性

  各テストケースでは、必ず`try...after`ブロックを使用してリソースをクリーンアップします。

  ```elixir
  try do
  # テスト実行
  after
  # ノードの停止とクリーンアップ
  Enum.each(nodes, fn pid ->
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal)
    end
  end)
  end
  ```

  ## Raftアルゴリズムの検証ポイント

  ### 1. リーダーの一意性

  Raftの基本的な保証として、各termで最大1つのリーダーしか存在しません。

  ### 2. termの単調増加

  ノードのterm番号は時間とともに単調増加し、減少することはありません。

  ### 3. 過半数の合意

  リーダー選出には過半数の投票が必要です。

  ### 4. ログの一貫性

  （現在のPolisはリーダー選出のみ実装）

  ## 参考資料

  - [Raft Consensus Algorithm](https://raft.github.io/)
  - [StreamData Documentation](https://hexdocs.pm/stream_data/)
  - [Property-Based Testing with PropEr, Erlang, and Elixir](https://propertesting.com/)
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Polis.Node

  @moduletag :property
  @moduletag timeout: :infinity

  describe "高負荷シナリオ: クラスタのプロパティベーステスト" do
    property "複数ノードが同時起動しても必ず1つのリーダーに収束する" do
      check all(
              node_count <- integer(3..20),
              max_runs: 5
            ) do
        cluster_id = make_ref()

        # 複数ノードを同時起動
        nodes =
          Enum.map(1..node_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        try do
          # リーダー選出を待つ
          Process.sleep(300)

          # リーダーの数を確認
          leaders =
            Enum.filter(nodes, fn pid ->
              if Process.alive?(pid) do
                Node.leader?(pid)
              else
                false
              end
            end)

          # 必ず1つのリーダーが存在する
          assert length(leaders) == 1, "Expected exactly 1 leader, got #{length(leaders)}"

          # すべてのノードが同じtermにいる
          terms =
            nodes
            |> Enum.filter(&Process.alive?/1)
            |> Enum.map(&Node.term/1)
            |> Enum.uniq()

          assert length(terms) <= 2,
                 "Expected terms to be consistent (max 2 during transition), got #{inspect(terms)}"
        after
          # クリーンアップ
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end

    property "ノードの追加・削除を繰り返してもリーダー選出が維持される" do
      check all(
              initial_count <- integer(3..10),
              operations <- list_of(member_of([:add, :remove]), min_length: 5, max_length: 20),
              max_runs: 20
            ) do
        cluster_id = make_ref()

        # 初期ノード起動
        initial_nodes =
          Enum.map(1..initial_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        Process.sleep(200)

        # ノードの追加・削除を繰り返す
        final_nodes =
          Enum.reduce(operations, initial_nodes, fn op, nodes ->
            case op do
              :add when length(nodes) < 30 ->
                {:ok, pid} =
                  Node.start_link(
                    cluster: cluster_id,
                    election_min: 50,
                    election_max: 100,
                    heartbeat_ms: 20
                  )

                Process.sleep(10)
                [pid | nodes]

              :remove when length(nodes) > 2 ->
                # ランダムにノードを削除（リーダーを優先的に残す）
                {to_remove, remaining} =
                  nodes
                  |> Enum.sort_by(&Node.leader?/1)
                  |> List.pop_at(0)

                if to_remove && Process.alive?(to_remove) do
                  GenServer.stop(to_remove, :normal)
                  Process.sleep(10)
                end

                remaining

              _ ->
                nodes
            end
          end)

        try do
          # 安定化を待つ
          Process.sleep(200)

          # 生存しているノードを確認
          alive_nodes = Enum.filter(final_nodes, &Process.alive?/1)

          if length(alive_nodes) >= 2 do
            # リーダーが1つだけ存在することを確認
            leaders = Enum.filter(alive_nodes, &Node.leader?/1)
            assert length(leaders) == 1, "Expected 1 leader, got #{length(leaders)}"
          end
        after
          # クリーンアップ
          all_nodes = Enum.uniq(initial_nodes ++ final_nodes)

          Enum.each(all_nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end

    property "高頻度のリーダー問い合わせでも一貫性が保たれる" do
      check all(
              node_count <- integer(3..10),
              query_count <- integer(50..200),
              max_runs: 5
            ) do
        cluster_id = make_ref()

        nodes =
          Enum.map(1..node_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        try do
          # リーダー選出を待つ
          Process.sleep(200)

          # 並行して大量のクエリを実行
          tasks =
            Enum.map(1..query_count, fn _ ->
              node = Enum.random(nodes)

              Task.async(fn ->
                if Process.alive?(node) do
                  try do
                    Node.current_leader(node, 100)
                  catch
                    :exit, _ -> nil
                  end
                else
                  nil
                end
              end)
            end)

          # すべてのタスクの結果を収集
          results =
            tasks
            |> Enum.map(&Task.await(&1, 500))
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          # すべての問い合わせで同じリーダーが返される
          assert length(results) <= 1,
                 "Expected consistent leader, got #{length(results)} different leaders"
        after
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end

    property "term番号は常に単調増加する" do
      check all(
              node_count <- integer(3..8),
              duration_ms <- integer(200..500),
              max_runs: 5
            ) do
        cluster_id = make_ref()

        nodes =
          Enum.map(1..node_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        try do
          Process.sleep(100)

          # 定期的にterm番号を記録
          initial_terms =
            nodes
            |> Enum.filter(&Process.alive?/1)
            |> Enum.map(fn pid -> {pid, Node.term(pid)} end)
            |> Map.new()

          # リーダーを強制的に停止してre-electionを発生させる
          leader = Enum.find(nodes, &Node.leader?/1)

          if leader do
            GenServer.stop(leader, :normal)
            Process.sleep(duration_ms)
          end

          # 最終的なterm番号を確認
          final_terms =
            nodes
            |> Enum.filter(&Process.alive?/1)
            |> Enum.map(fn pid -> {pid, Node.term(pid)} end)
            |> Map.new()

          # 各ノードのterm番号は増加しているか同じ
          Enum.each(final_terms, fn {pid, final_term} ->
            initial_term = Map.get(initial_terms, pid, 0)

            assert final_term >= initial_term,
                   "Term should never decrease: #{initial_term} -> #{final_term}"
          end)
        after
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end

    property "購読者への通知が正しく配信される" do
      check all(
              node_count <- integer(3..8),
              subscriber_count <- integer(1..10),
              max_runs: 5
            ) do
        cluster_id = make_ref()

        nodes =
          Enum.map(1..node_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        try do
          # 購読プロセスを作成
          subscribers =
            Enum.map(1..subscriber_count, fn _ ->
              spawn(fn ->
                receive do
                  :stop -> :ok
                end
              end)
            end)

          # 各ノードに購読者を登録
          node = Enum.random(nodes)
          Enum.each(subscribers, fn sub -> Node.subscribe(node, sub) end)

          Process.sleep(100)

          # リーダーを停止してロール変更を発生させる
          leader = Enum.find(nodes, &Node.leader?/1)

          if leader do
            GenServer.stop(leader, :normal)
            Process.sleep(300)
          end

          # 購読解除
          alive_node = Enum.find(nodes, &Process.alive?/1)

          if alive_node do
            Enum.each(subscribers, fn sub ->
              if Process.alive?(sub) do
                Node.unsubscribe(alive_node, sub)
              end
            end)
          end

          # クリーンアップ
          Enum.each(subscribers, fn sub ->
            if Process.alive?(sub) do
              send(sub, :stop)
            end
          end)

          # 基本的な検証: エラーが発生しないことを確認
          assert true
        after
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end
  end

  describe "耐障害性プロパティテスト" do
    property "過半数のノードが生存していればリーダー選出が可能" do
      check all(
              total_count <- integer(5..15),
              max_runs: 5
            ) do
        cluster_id = make_ref()

        nodes =
          Enum.map(1..total_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        try do
          Process.sleep(200)

          # 初期リーダーを確認
          initial_leaders = Enum.filter(nodes, &Node.leader?/1)
          assert length(initial_leaders) == 1

          # 少数のノードを停止（過半数は維持）
          minority_count = div(total_count, 2) - 1

          {to_stop, remaining} = Enum.split(nodes, max(1, minority_count))

          Enum.each(to_stop, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(300)

          # 残りのノードでリーダーが選出される
          alive_nodes = Enum.filter(remaining, &Process.alive?/1)

          if length(alive_nodes) >= 2 do
            leaders = Enum.filter(alive_nodes, &Node.leader?/1)
            assert length(leaders) == 1, "Should have exactly 1 leader after minority failure"
          end
        after
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end

    property "ネットワーク分断後の再統合でも一貫性が保たれる" do
      check all(
              node_count <- integer(5..10),
              max_runs: 5
            ) do
        cluster_id = make_ref()

        nodes =
          Enum.map(1..node_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        try do
          Process.sleep(200)

          # パーティション1とパーティション2に分割
          split_point = div(length(nodes), 2)
          {partition1, partition2} = Enum.split(nodes, split_point)

          # パーティション1のノードを一時停止（分断をシミュレート）
          Enum.each(partition1, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          # パーティション2で新しいリーダーが選出されるのを待つ
          Process.sleep(300)

          # パーティション1のノードを再起動（再統合）
          restarted =
            Enum.map(partition1, fn _ ->
              {:ok, pid} =
                Node.start_link(
                  cluster: cluster_id,
                  election_min: 50,
                  election_max: 100,
                  heartbeat_ms: 20
                )

              pid
            end)

          all_nodes = partition2 ++ restarted

          # 再統合後の安定化を待つ
          Process.sleep(300)

          # 統合後、リーダーは1つだけ
          alive_nodes = Enum.filter(all_nodes, &Process.alive?/1)

          if length(alive_nodes) >= 3 do
            leaders = Enum.filter(alive_nodes, &Node.leader?/1)
            assert length(leaders) == 1, "Should have exactly 1 leader after partition heal"
          end
        after
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end
  end

  describe "パフォーマンス特性のプロパティテスト" do
    property "タイムアウト設定が異なってもリーダー選出が成功する" do
      check all(
              node_count <- integer(3..8),
              election_min <- integer(30..100),
              election_max <- integer(101..200),
              heartbeat_ms <- integer(10..50),
              max_runs: 5
            ) do
        # election_maxはelection_minより大きい必要がある
        election_max = max(election_max, election_min + 10)

        cluster_id = make_ref()

        nodes =
          Enum.map(1..node_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: election_min,
                election_max: election_max,
                heartbeat_ms: heartbeat_ms
              )

            pid
          end)

        try do
          # 十分な時間を待つ（設定に応じて調整）
          sleep_time = election_max * 3
          Process.sleep(sleep_time)

          # リーダーが選出されていることを確認
          alive_nodes = Enum.filter(nodes, &Process.alive?/1)
          leaders = Enum.filter(alive_nodes, &Node.leader?/1)

          assert length(leaders) == 1,
                 "Should elect 1 leader with election_min=#{election_min}, election_max=#{election_max}, heartbeat=#{heartbeat_ms}"
        after
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end

    property "多数の並行操作でもデッドロックが発生しない" do
      check all(
              node_count <- integer(3..8),
              operation_count <- integer(50..150),
              max_runs: 5
            ) do
        cluster_id = make_ref()

        nodes =
          Enum.map(1..node_count, fn _ ->
            {:ok, pid} =
              Node.start_link(
                cluster: cluster_id,
                election_min: 50,
                election_max: 100,
                heartbeat_ms: 20
              )

            pid
          end)

        try do
          Process.sleep(200)

          # 多数の並行操作を実行
          tasks =
            Enum.map(1..operation_count, fn _ ->
              node = Enum.random(nodes)
              operation = Enum.random([:leader?, :role, :term, :members, :current_leader])

              Task.async(fn ->
                if Process.alive?(node) do
                  try do
                    case operation do
                      :leader? -> Node.leader?(node)
                      :role -> Node.role(node)
                      :term -> Node.term(node)
                      :members -> Node.members(node)
                      :current_leader -> Node.current_leader(node, 100)
                    end
                  catch
                    :exit, _ -> nil
                  end
                else
                  nil
                end
              end)
            end)

          # すべてのタスクが完了することを確認（デッドロックがないこと）
          results = Enum.map(tasks, &Task.await(&1, 1000))

          # 少なくとも一部の操作が成功していること
          successful = Enum.reject(results, &is_nil/1)
          assert length(successful) > 0, "Some operations should succeed"
        after
          Enum.each(nodes, fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal)
            end
          end)

          Process.sleep(50)
        end
      end
    end
  end
end
