# soba-cli

GitHub IssueとClaude Codeを連携させる自律的ワークフロー実行CLIツール

## インストール

```bash
# gemとしてインストール
gem install soba-cli
```

## セットアップ

```bash
# 開発用：依存関係のインストール
bundle install

# Git hooksの設定（Rubocop自動チェック）
./scripts/setup-hooks.sh
```

## 開発

### ディレクトリ構造

```
lib/
├── soba/
│   ├── cli/          # CLIコマンド定義
│   ├── commands/     # コマンド実装
│   ├── domain/       # ドメインモデル
│   ├── services/     # ビジネスロジック
│   └── infrastructure/ # 外部API連携
```

### テスト実行

```bash
# 全テスト実行
bundle exec rspec

# カバレッジ付きテスト
bundle exec rake coverage

# 特定のテストのみ
bundle exec rspec spec/unit/
```

### コード品質

```bash
# Rubocop実行（Airbnbスタイル）
bundle exec rubocop

# 自動修正
bundle exec rubocop -a

# セキュリティチェック
bundle exec bundler-audit
```

### 基本コマンド

```bash
# ヘルプ表示
bin/soba --help

# ワークフロー開始
bin/soba start

# ステータス確認
bin/soba status

# ワークフロー停止
bin/soba stop

# 設定確認
bin/soba config
```

## 設定

設定ファイル例: `~/.soba/config.yml`

```yaml
github:
  token: ${GITHUB_TOKEN}
  repository: owner/repo

claude:
  api_key: ${CLAUDE_API_KEY}

workflow:
  interval: 60
```

## Git Hooks

コミット時に自動でRubocopが実行されます：
- 自動修正可能な違反は修正
- 修正後は再ステージングを促すメッセージ表示
- 手動修正が必要な場合のみコミットをブロック

```bash
# hookをスキップする場合（非推奨）
git commit --no-verify
```

## ライセンス

MIT License