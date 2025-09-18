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
セッション名は以下の形式で統一されています：
```
soba-{repository}
```
- `repository`: GitHubリポジトリ名（スラッシュやドットはハイフンに変換）

#### ライフサイクル
1. **作成**: `find_or_create_repository_session` - リポジトリ用セッションを作成または取得
2. **ウィンドウ作成**: `create_issue_window` - Issue用ウィンドウを作成
3. **ペイン作成**: `create_phase_pane` - フェーズ用ペインを作成
4. **クリーンアップ**: 自動または手動でセッション・ウィンドウ・ペインを削除

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

クローズされたIssueのウィンドウは自動的に削除されます：
- `soba start`コマンド実行時に自動チェック
- GitHub APIでIssueステータスを確認
- クローズされたIssueのウィンドウを自動削除

## 使用例

### リポジトリセッションの作成

```ruby
# TmuxSessionManagerのインスタンス作成
manager = Soba::Services::TmuxSessionManager.new(
  tmux_client: Soba::Infrastructure::TmuxClient.new
)

# リポジトリセッションの作成または取得
result = manager.find_or_create_repository_session

if result[:success]
  session_name = result[:session_name]
  # => "soba-owner-repo"
end
```

### Issueウィンドウの作成

```ruby
# Issueごとのウィンドウを作成
window_result = manager.create_issue_window(
  session_name: "soba-owner-repo",
  issue_number: 42
)
# => {
#   success: true,
#   window_name: "issue-42",
#   created: true
# }
```

### 並行実行の管理

```ruby
# リポジトリセッション内で複数Issueを並行処理
session_result = manager.find_or_create_repository_session

[24, 25, 26].each do |issue_number|
  window_result = manager.create_issue_window(
    session_name: session_result[:session_name],
    issue_number: issue_number
  )

  pane_result = manager.create_phase_pane(
    session_name: session_result[:session_name],
    window_name: window_result[:window_name],
    phase: 'implementation'
  )
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

### クリーンアップ実行

```ruby
# クローズされたIssueのウィンドウを削除
manager = Soba::Services::TmuxSessionManager.new
sessions = manager.list_soba_sessions

sessions.each do |session_name|
  windows = @tmux_client.list_windows(session_name)
  windows.select { |w| w.start_with?('issue-') }.each do |window|
    issue_number = window.match(/issue-(\d+)/)[1]
    # GitHub APIでクローズ状態を確認して削除
  end
end
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

  it "creates repository session with correct name" do
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
  it "manages window lifecycle" do
    session = manager.find_or_create_repository_session
    window = manager.create_issue_window(
      session_name: session[:session_name],
      issue_number: 99
    )
    expect(window[:success]).to be true

    pane = manager.create_phase_pane(
      session_name: session[:session_name],
      window_name: window[:window_name],
      phase: 'test'
    )
    expect(pane[:success]).to be true
  end
end
```

## 注意事項

- tmuxセッションは手動でアタッチ可能（`tmux attach-session -t soba-{repository}`）
- リポジトリごとに1つのセッションを使用し、Issue単位でウィンドウを管理
- フェーズごとにペインを作成し、最大3ペインまで自動管理
- tmuxがインストールされていない環境では動作しない