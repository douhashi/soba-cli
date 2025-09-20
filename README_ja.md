# soba CLI

[![GitHub Release](https://img.shields.io/github/v/release/douhashi/soba-cli)](https://github.com/douhashi/soba-cli/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%203.0-red)](https://www.ruby-lang.org/)

[English version](README.md)

GitHub IssueとClaude Codeを連携させる自律的ワークフロー実行CLIツール。AI駆動の開発サイクルを実現します。

## 概要

soba CLIは、Issueの作成からプルリクエストのマージまで、開発ワークフロー全体を自動化します。GitHub Issueを監視し、Claude Code AIの支援により計画、実装、レビュー、マージの各フェーズを自動的に処理します。

## 主な機能

- 🤖 **自律ワークフロー**: Issue作成からマージまで完全自動化
- 🏷️ **ラベル駆動の状態管理**: GitHubラベルによる進捗追跡
- 🔄 **継続的処理**: 自動ポーリングとフェーズ遷移
- 🎯 **優先順位管理**: Issue番号による順次処理
- 🪟 **Tmux統合**: AIプロセスの可視化監視
- 🔀 **Git Worktreeサポート**: 独立したブランチ管理
- 🚀 **自動マージ**: 承認後の自動PRマージ

## ワークフロー

```mermaid
graph TD
    A[複数のsoba:todo] -->|soba: 優先度判定| B[1つをsoba:queued]
    B -->|soba: 即座に| C[soba:planning]
    C -->|Claude: 計画策定| D[soba:ready]
    D -->|soba: 自動検出| E[soba:doing]
    E -->|Claude: 実装・PR作成| F[soba:review-requested]
    F -->|soba: 自動検出| G[soba:reviewing]
    G -->|Claude: レビュー承認| H[soba:done + PR:soba:lgtm]
    G -->|Claude: 修正要求| I[soba:requires-changes]
    I -->|soba: 自動検出| K[soba:revising]
    K -->|Claude: 修正対応| F
    H -->|soba: 自動マージ| J[soba:merged]
    J -->|次のキューイング| A
```

## インストール

### Ruby Gemとして

```bash
gem install soba-cli
```

### ソースから

```bash
# リポジトリのクローン
git clone https://github.com/douhashi/soba-cli.git
cd soba-cli

# 依存関係のインストール
bundle install

# ソースから実行
bin/soba --help
```

## クイックスタート

1. **設定の初期化**
   ```bash
   soba init
   ```

2. **設定ファイルの編集**
   `.soba/config.yml`を編集:
   ```yaml
   github:
     token: ${GITHUB_TOKEN}
     repository: owner/repo
   ```

3. **自動化の開始**
   ```bash
   soba start
   ```

4. **ラベル付きIssueの作成**
   GitHub Issueに`soba:todo`ラベルを付けて自動処理を開始。

## 設定

設定ファイルの場所: `.soba/config.yml`（プロジェクトルート）

### 完全な設定例

```yaml
# GitHub設定
github:
  # Personal Access Token（環境変数可）
  token: ${GITHUB_TOKEN}
  # ターゲットリポジトリ（形式: owner/repo）
  repository: douhashi/soba-cli

# ワークフロー設定
workflow:
  # Issueポーリング間隔（秒）（デフォルト: 20）
  interval: 20
  # Claude実行にtmuxを使用（デフォルト: true）
  use_tmux: true
  # 自動PRマージ有効化（デフォルト: true）
  auto_merge_enabled: true
  # クローズ済みIssueのtmuxウィンドウクリーンアップ（デフォルト: true）
  closed_issue_cleanup_enabled: true
  # クリーンアップ間隔（秒）（デフォルト: 300）
  closed_issue_cleanup_interval: 300
  # tmuxペインへのコマンド遅延（秒）（デフォルト: 3）
  tmux_command_delay: 3

# Slack通知設定
slack:
  # Slack通知用のWebhook URL
  # Webhook URLの取得方法: https://api.slack.com/messaging/webhooks
  webhook_url: ${SLACK_WEBHOOK_URL}
  # フェーズ開始時の通知を有効化（デフォルト: false）
  notifications_enabled: false

# Git設定
git:
  # git worktreeのベースパス
  worktree_base_path: .git/soba/worktrees
  # フェーズ開始時の自動ワークスペース設定（デフォルト: true）
  setup_workspace: true

# フェーズコマンド（オプション - カスタムClaudeコマンド用）
phase:
  plan:
    command: claude
    options:
      - --dangerously-skip-permissions
    parameter: '/soba:plan {{issue-number}}'
  implement:
    command: claude
    options:
      - --dangerously-skip-permissions
    parameter: '/soba:implement {{issue-number}}'
  review:
    command: claude
    options:
      - --dangerously-skip-permissions
    parameter: '/soba:review {{issue-number}}'
  revise:
    command: claude
    options:
      - --dangerously-skip-permissions
    parameter: '/soba:revise {{issue-number}}'
```

### 環境変数

| 変数名 | 説明 | 必須 |
|--------|------|------|
| `GITHUB_TOKEN` | repoスコープを持つGitHub Personal Access Token | はい |

### Claudeコマンドテンプレート

Sobaは初期化時に自動的にClaudeコマンドテンプレートを `.claude/commands/soba/` に展開します。これらのテンプレートは各フェーズのワークフロー自動化コマンドを定義します：

- **plan.md** - Issue計画フェーズテンプレート
- **implement.md** - 実装フェーズテンプレート
- **review.md** - PRレビューフェーズテンプレート
- **revise.md** - 修正フェーズテンプレート

これらのテンプレートはgemパッケージに含まれており、以下で確認できます：
[lib/soba/templates/claude_commands/](lib/soba/templates/claude_commands/)

## コマンド

### `soba init`
現在のプロジェクトでsoba設定を初期化。

```bash
# 基本的な初期化
soba init

# インタラクティブモード
soba init --interactive
```

### `soba start`
ワークフロー自動化デーモンを開始。

```bash
# デーモンモード（バックグラウンド）で開始
soba start

# フォアグラウンドモードで開始
soba start --foreground

# 特定のIssueを指定して開始
soba start 123

# tmuxなしで開始
soba start --no-tmux
```

### `soba status`
デーモンのステータスと最近のログを表示。

```bash
# 基本ステータス
soba status

# より多くのログ行を表示
soba status --log 50

# JSON形式で出力
soba status --json
```

### `soba stop`
実行中のデーモンを停止。

```bash
# 正常停止
soba stop

# 即座に強制停止
soba stop --force

# カスタムタイムアウト
soba stop --timeout 60
```

### `soba open`
タスクのtmuxセッションを開くまたは一覧表示。

```bash
# 特定のタスクセッションを開く
soba open 123

# すべてのアクティブなセッションを一覧表示
soba open --list
```

### `soba config`
現在の設定を表示。

```bash
# 設定を表示
soba config

# 特定の設定ファイルを使用
soba --config /path/to/config.yml config
```

## ラベルシステム

### Issueラベル（状態管理）

| ラベル | 状態 | 説明 |
|--------|------|------|
| `soba:todo` | 待機 | 新規Issue、処理待ち |
| `soba:queued` | キュー選択 | 処理対象として選択済み |
| `soba:planning` | 計画中 | Claudeが実装計画を策定中 |
| `soba:ready` | 準備完了 | 計画完了、実装待ち |
| `soba:doing` | 実装中 | Claudeが実装作業中 |
| `soba:review-requested` | レビュー待ち | PR作成済み、レビュー待ち |
| `soba:reviewing` | レビュー中 | ClaudeがPRをレビュー中 |
| `soba:done` | 完了 | レビュー承認済み、マージ可能 |
| `soba:requires-changes` | 修正要求 | レビューで修正が必要と判断 |
| `soba:revising` | 修正中 | Claudeが修正対応中 |
| `soba:merged` | マージ済み | PRマージ済み、Issueクローズ済み |

### PRラベル

| ラベル | 説明 |
|--------|------|
| `soba:lgtm` | レビュー承認済み、自動マージ対象 |

## 開発

### ディレクトリ構造

```
lib/
├── soba/
│   ├── cli/              # CLIフレームワーク設定
│   ├── commands/         # コマンド実装
│   ├── domain/           # ドメインモデル
│   ├── services/         # ビジネスロジック
│   └── infrastructure/   # 外部連携
```

### テストの実行

```bash
# 全テスト実行
bundle exec rspec

# カバレッジ付きテスト
bundle exec rake coverage

# 特定のテストスイート実行
bundle exec rspec spec/unit/
```

### コード品質

```bash
# Rubocop実行（Airbnbスタイル）
bundle exec rubocop

# 自動修正
bundle exec rubocop -a

# セキュリティ監査
bundle exec bundler-audit
```

### Gitフック

プロジェクトはコード品質のためのpre-commitフックを使用：
- 自動的なRubocop修正
- 自動修正後の再ステージング
- 手動修正が必要な場合のコミットブロック

フックのセットアップ：
```bash
./scripts/setup-hooks.sh
```

## 要件

- Ruby >= 3.0
- Git
- tmux（オプション、推奨）
- GitHub Personal Access Token
- Claude Code CLI（`claude`コマンド）

## アーキテクチャ

soba CLIはレイヤードアーキテクチャに従っています：
- **Commandsレイヤー**: CLIコマンド定義と解析
- **Domainレイヤー**: コアビジネスモデルとロジック
- **Servicesレイヤー**: ワークフローオーケストレーションと状態管理
- **Infrastructureレイヤー**: GitHub APIと外部ツール統合

詳細なアーキテクチャドキュメントは[docs/development/architecture.md](docs/development/architecture.md)を参照。

## コントリビューション

1. リポジトリをフォーク
2. フィーチャーブランチを作成（`git checkout -b feature/amazing-feature`）
3. 変更をコミット（`git commit -m 'Add amazing feature'`）
4. ブランチにプッシュ（`git push origin feature/amazing-feature`）
5. プルリクエストを開く

以下を確認してください：
- すべてのテストがパス（`bundle exec rspec`）
- Rubocopチェックがパス（`bundle exec rubocop`）
- 高いコードカバレッジを維持

## ライセンス

このプロジェクトはMITライセンスの下でライセンスされています - 詳細は[LICENSE](LICENSE)ファイルを参照。

## サポート

- **Issues**: [GitHub Issues](https://github.com/douhashi/soba-cli/issues)
- **Discussions**: [GitHub Discussions](https://github.com/douhashi/soba-cli/discussions)

## 謝辞

- AI駆動開発を実現する[Claude Code](https://claude.ai/code)
- CLIフレームワーク[GLI](https://github.com/davetron5000/gli)
- [Airbnb Ruby Style Guide](https://github.com/airbnb/ruby)によるスタイリング