# soba 自動ワークフロー

## 概要

sobaは、GitHub Issueを起点とした自律的な開発ワークフローを実現します。Issue のラベルに基づいて自動的に計画と実装のサイクルを実行します。

## ワークフローの流れ

```mermaid
graph TD
    A[soba:todo] -->|soba: 自動検出| B[soba:planning]
    B -->|Claude: 計画策定| C[soba:ready]
    C -->|soba: 自動検出| D[soba:doing]
    D -->|Claude: 実装・PR作成| E[soba:review-requested]
    E -->|soba: 自動検出| F[soba:reviewing]
    F -->|Claude: レビュー承認| G[soba:done]
    F -->|Claude: 修正要求| H[soba:requires-changes]
```

## 計画フェーズ

### 1. Issue検出
- **対象ラベル**: `soba:todo`
- **検出方法**: 定期的なGitHub Issue監視
- **選定基準**: Issue番号が最も若いものを1件抽出
- **実行主体**: **soba CLI**

### 2. 計画策定
- **【soba】** ラベルを `soba:todo` → `soba:planning` に変更
- **【soba】** Claude Codeプロセスを起動
- **【Claude】** Issueの内容を分析し、実装計画を策定
- **【Claude】** 策定完了後、ラベルを `soba:planning` → `soba:ready` に変更

## 実装フェーズ

### 1. Issue検出
- **対象ラベル**: `soba:ready`
- **検出方法**: 定期的なGitHub Issue監視
- **選定基準**: Issue番号が最も若いものを1件抽出
- **実行主体**: **soba CLI**

### 2. 実装作業
- **【soba】** ラベルを `soba:ready` → `soba:doing` に変更
- **【soba】** Claude Codeプロセスを起動
- **【Claude】** 以下を自動実行：
  - Issueの実装
  - セルフレビュー
  - Pull Request作成
- **【Claude】** 完了後、ラベルを `soba:doing` → `soba:review-requested` に変更

## レビューフェーズ

### 1. Issue検出
- **対象ラベル**: `soba:review-requested`
- **検出方法**: 定期的なGitHub Issue監視
- **選定基準**: Issue番号が最も若いものを1件抽出
- **実行主体**: **soba CLI**

### 2. レビュー実施
- **【soba】** ラベルを `soba:review-requested` → `soba:reviewing` に変更
- **【soba】** Claude Codeプロセスを起動
- **【Claude】** PRの内容をレビューし、以下を実行：
  - コード品質のチェック
  - テスト実行状況の確認
  - セキュリティ観点でのチェック
  - レビューコメントの投稿
- **【Claude】** レビュー結果に応じてラベルを変更：
  - 承認: `soba:reviewing` → `soba:done`
  - 修正要求: `soba:reviewing` → `soba:requires-changes`

## ラベル定義

| ラベル | 状態 | 説明 | 変更主体 |
|--------|------|------|----------|
| `soba:todo` | 待機 | 新規Issue、計画待ち | - |
| `soba:planning` | 計画中 | Claude Codeが計画策定中 | soba → |
| `soba:ready` | 準備完了 | 計画策定済み、実装待ち | Claude → |
| `soba:doing` | 実装中 | Claude Codeが実装作業中 | soba → |
| `soba:review-requested` | レビュー待ち | PR作成済み、レビュー待ち | Claude → |
| `soba:reviewing` | レビュー中 | Claude Codeがレビュー実施中 | soba → |
| `soba:done` | 完了 | レビュー承認、マージ可能 | Claude → |
| `soba:requires-changes` | 修正要求 | レビューで修正が必要と判断 | Claude → |

## 自動化のメリット

1. **継続的な進捗**: Issueが自動的に処理され、開発が停滞しない
2. **一貫性**: 同じプロセスで全てのIssueを処理
3. **効率化**: 手動でのラベル変更やプロセス起動が不要
4. **優先順位管理**: Issue番号順による明確な処理順序
