---
allowed-tools: TodoWrite, TodoRead, Bash, Read, Grep, Glob, LS
description: "Create implementation plan"
---

## Overview

You are a capable software architect.  
Your task is to create an Implementation Plan (Plan) for a given GitHub Issue, including technical investigation, design decisions, task breakdown, test planning, and risk assessment, and post it as a comment on the Issue.

---

## Prerequisites

### Documents

Please refer to the relevant documents via the following index files (Document System format):

- **Coding Standards**: @docs/development/coding-standards.md
- **Testing Strategy**: @docs/development/testing-strategy.md
- **Other Development Documents**: @docs/development/INDEX.md

### Expected State of the Issue

- Acceptance criteria are clearly written in the GitHub Issue  

---

## Rules

1. **Do not modify code; focus solely on creating the plan**
2. **Design the plan with TDD and testability in mind**
3. **Follow the existing system architecture**
4. **Break the plan into step-by-step, executable units**
5. **Use the predefined template format when writing the plan**
6. **Update the label to `status:ready` upon completion**
7. **When researching libraries, use `use context7 mcp` to always refer to the latest official documentation**

---

## Instructions

### High-Level Workflow

1. Confirm the target Issue
2. Investigate relevant code and architecture
3. Choose a technical approach
4. Define task steps and test coverage
5. Document risks and schedule
6. Write the plan to a file
7. Post the plan as a comment to the Issue
8. Update the Issue label

---

### Detailed Steps

1. **Confirm the target Issue**
   - Run `gh issue view <issue number>` and check:
     - Title, background, user story, and acceptance criteria
   - Run `gh issue view <issue number> --comments` and check:
     - Additional information, user approval, or clarifications in comments

2. **Investigate codebase and system structure**
   - Review related source files, config files, and similar past implementations
   - Identify impact areas and dependencies

3. **Choose a technical approach**
   - Specify libraries, design patterns, and frameworks to use
   - Clearly state reasoning and alternatives considered

4. **Break down the implementation into steps**
   - Ensure each step is testable and small enough for incremental progress
   - Include notes on related files, side effects, and prerequisites

5. **Describe test strategy, risks, and schedule**
   - Outline unit, integration, and E2E test plans
   - List possible technical risks and mitigation strategies
   - Define estimated duration and key checkpoints

6. **Write the implementation plan to a file**
   - Use the implementation plan template and save to `./.tmp/plan-[slug].md`
   - Replace `[slug]` with a kebab-case version of the issue title (e.g., `plan-add-favorite.md`)

7. **Post the plan as a comment**
   - Run: `gh issue comment <issue number> --body-file ./.tmp/plan-[slug].md`

8. **Update the label**
   - Run: `gh issue edit <issue number> --remove-label "status:planning" --add-label "status:ready"`

---

## Plan template

```
# 実行計画: [タイトル]

## 前提知識
- [関連技術・既存システムの構造]
- [考慮すべき制約]
- [参考資料・ドキュメント]

## 要件概要
- [要件の概要と目的]
- [機能要件]
- [非機能要件（例：性能、セキュリティ）]
- [受け入れ条件]

## 設計方針
- [使用する技術や設計パターン]
- [構成方針や判断理由]
- [考慮したアーキテクチャ上のポイント]

## 実装ステップ
1. [ステップ1]
   - [具体的な作業内容]
   - [関係するファイルや関数など]
2. [ステップ2]
   - [同上]

## テスト計画
- ユニットテスト：
  - [テスト対象]
  - [テストケース（正常系／異常系）]
- 結合・システムテスト：
  - [検証すべきユーザーフローやパターン]
- テストデータ：
  - [準備すべき入力データや事前状態の例]

## リスクと対策
- [想定されるリスク1]
  - [対策案]
- [想定されるリスク2]
  - [対策案]

## タイムライン
- 実装期間の目安: [開始日] 〜 [終了日]
- 各ステップの予想時間（単位: 時間）:
  - ステップ1: [X時間]
  - ステップ2: [X時間]
```

## Plan example

```
# 実行計画: 商品にお気に入り機能を追加する

## 前提知識
- Webアプリは Vue 3 + Rails API で構成されている
- ユーザー認証は Devise Token Auth により実装されている
- フロントエンドは Pinia により状態管理されている
- お気に入り状態はユーザー単位で永続化される必要がある
- `products` テーブルは既に存在し、IDと基本情報を保持している

## 要件概要
- 商品に「お気に入り」ボタン（ハートアイコン）を追加する
- ユーザーは任意の商品をお気に入りリストに追加・削除できる
- お気に入り一覧ページで、自身が登録した商品だけを確認できる
- 非ログイン状態ではボタンを表示しない
- パフォーマンス要件：追加・削除は非同期、レスポンス200ms以内

## 設計方針
- フロントエンドは `<FavoriteButton>` コンポーネントを導入して再利用可能にする
- バックエンドは `favorites` テーブル（user_id, product_id）を新設し、RESTful APIで操作する
- フロント側は Pinia でお気に入り状態をキャッシュ保持し、APIとの同期を行う
- ユーザー認証済みでない場合、ボタンを非表示にする

## 実装ステップ
1. `favorites` テーブルの追加
   - migration を作成し、ユニーク制約 (user_id, product_id) を設定
   - index を追加して高速化

2. APIエンドポイントの作成
   - `POST /api/favorites`（追加）
   - `DELETE /api/favorites/:id`（削除）
   - `GET /api/favorites`（一覧取得）

3. フロントの状態管理構築
   - Piniaストアでお気に入り状態を保持
   - 初回ロード時に `/favorites` を取得

4. `<FavoriteButton>` コンポーネントの作成
   - 状態に応じてアイコン切替（空白ハート↔実心ハート）
   - ボタンクリックで追加／削除APIを呼び出す

5. 商品カードおよび詳細ページへのボタン配置
   - `ProductCard.vue` および `ProductDetail.vue` に設置

## テスト計画
- ユニットテスト：
  - FavoriteStore（状態切替の確認）
  - FavoriteButton（UIの状態／クリック挙動）

- 結合・システムテスト：
  - ログイン → 商品一覧表示 → ハートを押して追加／削除できる
  - 非ログイン時にはボタンが表示されないこと

- テストデータ：
  - ユーザー：ログイン済みのダミーユーザー
  - 商品：product_id = 1〜3 の仮データを用意

## リスクと対策
- お気に入りの二重登録
  - 対策：DBにユニークインデックスを設定
- お気に入りの状態同期ミス
  - 対策：非同期APIのレスポンスに基づいて状態を確定させる

## タイムライン
- 実装期間の目安: 2025-07-22 〜 2025-07-24
- 各ステップの予想時間（単位: 時間）:
  - ステップ1: 1.5h
  - ステップ2: 2.0h
  - ステップ3: 1.5h
  - ステップ4: 2.0h
  - ステップ5: 1.0h
  - テスト＆検証: 1.5h
```
