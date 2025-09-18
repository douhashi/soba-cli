# tmux管理機能

## 概要

sobaのtmux管理機能は、Claude Codeの実行環境をtmuxセッション内で分離・管理することで、長時間実行される処理の監視や並行実行を可能にします。

## アーキテクチャ

### コンポーネント構成

```
┌────────────────────────────┐
│  WorkflowExecutor          │ → ワークフロー実行制御
└────────┬───────────────────┘
         │
         ▼
┌────────────────────────────┐
│  TmuxSessionManager        │ → セッション管理ロジック
└────────┬───────────────────┘
         │
         ▼
┌────────────────────────────┐
│  TmuxClient               │ → tmuxコマンドラッパー
└────────────────────────────┘
```

### 責務分担

| コンポーネント | 責務 |
|--------------|------|
| **TmuxSessionManager** | セッションライフサイクル管理、命名規則の実装、古いセッションのクリーンアップ |
| **TmuxClient** | tmuxコマンドの実行、エラーハンドリング、出力のパース |

## 主要機能

### セッション管理

#### 命名規則
セッション名は以下の形式で管理されます：
```
soba-{repository}
```
- `repository`: GitHubリポジトリ名（スラッシュ等の特殊文字はハイフンに置換）

#### ライフサイクル
1. **作成**: `find_or_create_repository_session` - リポジトリセッションを作成/取得
2. **ウィンドウ作成**: `create_issue_window` - Issue用のウィンドウを作成
3. **ペイン作成**: `create_phase_pane` - フェーズ実行用のペインを作成
4. **削除**: tmuxコマンドで手動削除またはシステム終了時

### ペイン操作

#### 基本操作
- `send_keys`: コマンドをペインに送信
- `capture_pane`: ペイン出力をキャプチャ
- `capture_pane_continuous`: 出力を継続的に監視（ストリーミング）

#### 高度な操作
- `split_pane`: ペインの分割（水平/垂直）
- `resize_pane`: ペインサイズ調整
- `select_pane`: アクティブペインの切り替え
- `list_panes`: ペイン一覧と作成時刻の取得
- `kill_pane`: 指定ペインの削除
- `select_layout`: レイアウトの自動調整

### ペイン管理の自動化

#### ペイン数制限機能
フェーズ実行時に自動的にペイン数を管理：
- **最大ペイン数**: デフォルトで3つに制限
- **自動削除**: 4つ目のペイン作成時に最古のペインを自動削除
- **作成時刻追跡**: `#{pane_start_time}`フォーマットを使用

#### レイアウト自動調整
ペイン作成・削除後に自動的にレイアウトを調整：
- **水平分割**: フェーズ実行時のデフォルト（`vertical: false`）
- **自動調整**: `even-horizontal`レイアウトを適用
- **均等配置**: すべてのペインが同じ幅になるよう調整

### 自動クリーンアップ

新形式では、リポジトリごとに1つのセッションを維持し、Issueごとにウィンドウを作成するため、
古いセッションのクリーンアップは不要になりました。

## 使用例

### リポジトリセッションとIssueウィンドウの作成

```ruby
# TmuxSessionManagerのインスタンス作成
manager = Soba::Services::TmuxSessionManager.new(
  tmux_client: Soba::Infrastructure::TmuxClient.new
)

# リポジトリセッションの作成/取得
result = manager.find_or_create_repository_session
if result[:success]
  session_name = result[:session_name]
  # => "soba-owner-repo"

  # Issue用ウィンドウの作成
  window_result = manager.create_issue_window(
    session_name: session_name,
    issue_number: 24
  )
  # => { success: true, window_name: "issue-24", created: true }
end
```

### 並行実行の管理

```ruby
# 1つのリポジトリセッション内で複数のIssueを並行処理
session_result = manager.find_or_create_repository_session
session_name = session_result[:session_name]

# 複数のIssue用ウィンドウを作成
[24, 25, 26].each do |issue_number|
  window_result = manager.create_issue_window(
    session_name: session_name,
    issue_number: issue_number
  )

  if window_result[:success]
    puts "Issue ##{issue_number}: window created - #{window_result[:window_name]}"
  end
end
```

### フェーズごとのペイン管理

```ruby
# リポジトリセッションとIssueウィンドウの作成
session_result = manager.find_or_create_repository_session
window_result = manager.create_issue_window(
  session_name: session_result[:session_name],
  issue_number: 42
)

# フェーズごとにペインを作成（水平分割、最大3ペイン）
phases = ['planning', 'implementation', 'review', 'testing']
phases.each do |phase|
  pane_result = manager.create_phase_pane(
    session_name: session_result[:session_name],
    window_name: window_result[:window_name],
    phase: phase,
    vertical: false,  # 水平分割
    max_panes: 3     # 最大3ペイン（4つ目から古いペインを削除）
  )

  if pane_result[:success]
    puts "Phase #{phase} started in pane #{pane_result[:pane_id]}"
  end
end
```

### Issueウィンドウの検索

```ruby
# 特定のIssueのウィンドウを検索
window_target = manager.find_issue_window('owner/repo', 42)
# => "soba-owner-repo:issue-42" or nil

# リポジトリ内の全Issueウィンドウを一覧表示
windows = manager.list_issue_windows('owner/repo')
# => [{ window: "issue-42", title: "Fix bug" }, ...]
```

## エラーハンドリング

### TmuxNotInstalled例外
tmuxがインストールされていない場合に発生：

```ruby
begin
  client.create_session("test")
rescue Soba::Infrastructure::TmuxNotInstalled => e
  puts "tmuxをインストールしてください"
end
```

### ウィンドウ作成失敗
セッションが存在しない場合など：

```ruby
result = manager.create_issue_window(
  session_name: "non-existent",
  issue_number: 24
)
if !result[:success]
  puts "エラー: #{result[:error]}"
end
```

## テスト戦略

### モックを使用した単体テスト
```ruby
RSpec.describe Soba::Services::TmuxSessionManager do
  let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }

  it "creates repository session with correct name format" do
    allow(tmux_client).to receive(:session_exists?).and_return(false)
    allow(tmux_client).to receive(:create_session).and_return(true)

    result = manager.find_or_create_repository_session
    expect(result[:session_name]).to match(/^soba-[\w-]+$/)
  end
end
```

### 実環境での統合テスト
```ruby
RSpec.describe "Tmux Integration", integration: true do
  it "manages repository session and issue windows" do
    # リポジトリセッション作成
    session_result = manager.find_or_create_repository_session
    expect(session_result[:success]).to be true

    # Issueウィンドウ作成
    window_result = manager.create_issue_window(
      session_name: session_result[:session_name],
      issue_number: 99
    )
    expect(window_result[:success]).to be true

    # フェーズペイン作成
    pane_result = manager.create_phase_pane(
      session_name: session_result[:session_name],
      window_name: window_result[:window_name],
      phase: 'testing'
    )
    expect(pane_result[:success]).to be true
  end
end
```

## 注意事項

- tmuxセッションは手動でアタッチ可能（`tmux attach-session -t セッション名`）
- リポジトリごとに1つのセッションを維持し、Issueごとにウィンドウを作成
- セッション名は`soba-{repository}`形式で統一
- tmuxがインストールされていない環境では動作しない