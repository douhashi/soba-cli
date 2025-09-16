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
セッション名は以下の形式で自動生成されます：
```
soba-claude-{issue_number}-{timestamp}
```
- `issue_number`: GitHub Issue番号
- `timestamp`: Unix timestamp

#### ライフサイクル
1. **作成**: `start_claude_session` - 新規セッションを作成しコマンド実行
2. **監視**: `get_session_status` - セッション状態と出力を取得
3. **接続**: `attach_to_session` - 既存セッションにアタッチ
4. **削除**: `stop_claude_session` - セッションを終了

### ペイン操作

#### 基本操作
- `send_keys`: コマンドをペインに送信
- `capture_pane`: ペイン出力をキャプチャ
- `capture_pane_continuous`: 出力を継続的に監視（ストリーミング）

#### 高度な操作
- `split_pane`: ペインの分割（水平/垂直）
- `resize_pane`: ペインサイズ調整
- `select_pane`: アクティブペインの切り替え

### 自動クリーンアップ

`cleanup_old_sessions`メソッドによる古いセッションの自動削除：
- デフォルト: 1時間（3600秒）以上経過したセッションを削除
- タイムスタンプベースの判定
- `soba-claude-`プレフィックスのセッションのみ対象

## 使用例

### Claude実行環境の起動

```ruby
# TmuxSessionManagerのインスタンス作成
manager = Soba::Services::TmuxSessionManager.new(
  tmux_client: Soba::Infrastructure::TmuxClient.new
)

# Claude実行セッションの開始
result = manager.start_claude_session(
  issue_number: 24,
  command: "soba:implement"
)

if result[:success]
  session_name = result[:session_name]
  # => "soba-claude-24-1735123456"
end
```

### セッション状態の確認

```ruby
status = manager.get_session_status(session_name)
# => {
#   exists: true,
#   status: "running",
#   last_output: "実行ログ..."
# }
```

### 並行実行の管理

```ruby
# 複数のIssueを並行処理
sessions = []
[24, 25, 26].each do |issue_number|
  result = manager.start_claude_session(
    issue_number: issue_number,
    command: "soba:plan"
  )
  sessions << result[:session_name]
end

# 全セッションの監視
sessions.each do |session|
  status = manager.get_session_status(session)
  puts "#{session}: #{status[:status]}"
end
```

### クリーンアップ実行

```ruby
# 30分以上経過したセッションを削除
result = manager.cleanup_old_sessions(max_age_seconds: 1800)
# => { cleaned: ["soba-claude-22-1735120000", ...] }
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

### セッション作成失敗
すでに同名のセッションが存在する場合など：

```ruby
result = manager.start_claude_session(issue_number: 24, command: "cmd")
if !result[:success]
  puts "エラー: #{result[:error]}"
end
```

## テスト戦略

### モックを使用した単体テスト
```ruby
RSpec.describe Soba::Services::TmuxSessionManager do
  let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }

  it "creates session with correct name format" do
    allow(tmux_client).to receive(:create_session).and_return(true)
    allow(tmux_client).to receive(:send_keys).and_return(true)

    result = manager.start_claude_session(issue_number: 24, command: "test")
    expect(result[:session_name]).to match(/^soba-claude-24-\d+$/)
  end
end
```

### 実環境での統合テスト
```ruby
RSpec.describe "Tmux Integration", integration: true do
  it "manages session lifecycle" do
    result = manager.start_claude_session(issue_number: 99, command: "echo test")
    expect(result[:success]).to be true

    status = manager.get_session_status(result[:session_name])
    expect(status[:exists]).to be true

    manager.stop_claude_session(result[:session_name])
  end
end
```

## 注意事項

- tmuxセッションは手動でアタッチ可能（`tmux attach-session -t セッション名`）
- 長時間実行されるセッションは定期的なクリーンアップが必要
- セッション名の重複を避けるためタイムスタンプを使用
- tmuxがインストールされていない環境では動作しない