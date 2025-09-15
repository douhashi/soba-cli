# soba CLI アーキテクチャ設計書

## 概要

GitHub IssueとClaude Codeを連携させる自律的ワークフロー実行ツールのアーキテクチャ。

## レイヤー構成

```
┌─────────────────────────────────────┐
│   CLI (GLI)                         │ → コマンドインターフェース
├─────────────────────────────────────┤
│   Commands                          │ → コマンド処理
├─────────────────────────────────────┤
│   Services                          │ → ビジネスロジック
├─────────────────────────────────────┤
│   Domain                            │ → ドメインモデル
├─────────────────────────────────────┤
│   Infrastructure                    │ → 外部連携
└─────────────────────────────────────┘
```

## ディレクトリ構造

```
soba/
├── bin/soba                # 実行ファイル
├── lib/soba/
│   ├── cli/               # CLIコマンド定義
│   ├── commands/          # コマンド実装
│   ├── services/          # ビジネスロジック
│   ├── domain/            # エンティティ、値オブジェクト
│   └── infrastructure/    # GitHub/Claude API連携
├── spec/                  # テスト
└── config/               # 設定ファイル
```

## 主要コンポーネント

| コンポーネント | ライブラリ | 用途 |
|-------------|----------|------|
| CLI | GLI | コマンドライン処理 |
| DI | dry-container | 依存性注入 |
| HTTP | Faraday + Octokit | API通信 |
| 非同期 | concurrent-ruby | 並行処理 |
| ログ | semantic_logger | ログ出力 |

## データフロー

```
User → CLI → Command → Service → Domain
                ↓
        Infrastructure → External API
```

## 設定ファイル

```yaml
# ~/.soba/config.yml
github:
  token: ${GITHUB_TOKEN}
  repository: owner/repo

claude:
  api_key: ${CLAUDE_API_KEY}

workflow:
  interval: 60
```