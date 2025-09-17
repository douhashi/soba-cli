# soba 自動ワークフロー

## 概要

sobaは、GitHub Issueを起点とした自律的な開発ワークフローを実現します。Issue のラベルに基づいて自動的に計画と実装のサイクルを実行します。

## ワークフローの流れ

```mermaid
graph TD
    A[複数のsoba:todo] -->|soba: 優先度判定| B[1つをsoba:queued]
    B -->|soba: 即座に| C[soba:planning]
    C -->|Claude: 計画策定| D[soba:ready]
    D -->|soba: 自動検出| E[soba:doing]
    E -->|Claude: 実装・PR作成| F[soba:review-requested]
    F -->|soba: 自動検出| G[soba:reviewing]
    G -->|Claude: レビュー承認| H[soba:done]
    G -->|Claude: 修正要求| I[soba:requires-changes]
    H -->|次のキューイング| A
```

## 計画フェーズ

### 1. Issue検出
- **対象ラベル**: `soba:todo`
- **検出方法**: 定期的なGitHub Issue監視
- **選定基準**: Issue番号が最も若いものを1件抽出
- **実行主体**: **soba CLI**

### 2. キューイング・計画策定
- **【soba】** 複数の `soba:todo` から Issue番号が最も若いものを選択
- **【soba】** ラベルを `soba:todo` → `soba:queued` → `soba:planning` に変更
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
| `soba:todo` | 待機 | 新規Issue、計画待ち（複数設定可） | - |
| `soba:queued` | キュー選択 | 優先度判定で選択済み（1つのみ） | soba → |
| `soba:planning` | 計画中 | Claude Codeが計画策定中（1つのみ） | soba → |
| `soba:ready` | 準備完了 | 計画策定済み、実装待ち | Claude → |
| `soba:doing` | 実装中 | Claude Codeが実装作業中（1つのみ） | soba → |
| `soba:review-requested` | レビュー待ち | PR作成済み、レビュー待ち | Claude → |
| `soba:reviewing` | レビュー中 | Claude Codeがレビュー実施中（1つのみ） | soba → |
| `soba:done` | 完了 | レビュー承認、マージ可能 | Claude → |
| `soba:requires-changes` | 修正要求 | レビューで修正が必要と判断 | Claude → |

## 自動化のメリット

1. **継続的な進捗**: Issueが自動的に処理され、開発が停滞しない
2. **一貫性**: 同じプロセスで全てのIssueを処理
3. **効率化**: 手動でのラベル変更やプロセス起動が不要
4. **優先順位管理**: Issue番号順による明確な処理順序
5. **厳密な排他制御**: 常に1つのIssueのみがアクティブ処理される
