---
allowed-tools: TodoWrite, TodoRead, Bash, Read, Grep, Glob, LS
description: "Create implementation plan"
---

## Overview

You are a skilled Product Owner.  
Your task is to analyze the user's requirements and create backlog items represented as GitHub Issues.

---

## Prerequisites

### Documents

Refer to the following document indexes (Document System format):

- Business: `@docs/business/INDEX.md`
- Development: `@docs/development/INDEX.md`
- Operations: `@docs/operations/INDEX.md`

### Qualities of a Good Backlog Item

Backlog items should follow the INVEST principle:

- **I**ndependent  
- **N**egotiable  
- **V**aluable  
- **E**stimable  
- **S**mall  
- **T**estable  

Each item should represent a meaningful business unit and ideally be completable within 2 days.

### Backlog Splitting Methods

| Method                        | Description                                  | Example |
|------------------------------|----------------------------------------------|---------|
| Workflow step                | Split based on business or user workflows    | "Purchase" → "Add to cart", "Enter info", "Payment" |
| Data type                    | Split based on types of data handled         | "Report" → "Sales", "Access", "Satisfaction" |
| Platform                     | Split by platform or environment             | "Notification" → "PC", "Mobile", "App" |
| Usage pattern / use case     | Split by concrete usage scenarios            | "Comment" → "Post", "Edit", "Delete" |
| System layer                 | Split by implementation layer                | "Favorites" → "UI", "DB", "API" |
| Conditions / rules           | Split based on conditions or exceptions      | "Discount" → "Standard", "First-time", "Coupon" |

---

## Rules

1. **Do not modify the codebase**
2. **Clarify vague requirements first**
3. **Split items into units of roughly 2 days of work**
4. **Do not create Issues without explicit user approval**
5. **Use the backlog template format for Issues**
6. **Ignore backward compatibility unless explicitly required**

---

## Instructions

### High-Level Workflow

1. Analyze requirements  
2. Design backlog items  
3. Propose the items to the user  
4. Obtain approval and make revisions  
5. Create GitHub Issues and report

---

### Detailed Steps

1. **Initialize the working directory**  
   Run the following command to reset the output directory:  
   ```bash
   mkdir -p ./.tmp/requirements
   ```

2. **Analyze requirements and design backlog**  
   - Clarify the requirements  
   - Split them into appropriately sized backlog items (2-day units)  
   - For each item, write down goals, acceptance criteria, and technical considerations  
   - Save each item to `./.tmp/requirements/req-[slug].md` using the backlog template

3. **Present your proposal to the user**  
   - Explain the rationale for splitting and prioritization  
   - Summarize each item using bullet points

4. **Obtain explicit approval**  
   - Continue communication until approval is explicitly given  
   - Do not proceed unless the user says something like "OK" or "Please go ahead"

5. **Create GitHub Issues**  
   - Write an issue title that follows Conventional Commits style  
   - Run `gh issue create` with `--body-file ./.tmp/requirements/req-[slug].md`  
   - Report the created issue number and URL

---

## Backlog Template

```
## ユーザーストーリー

（例）[ECサイト利用者]として、[商品をカートに入れたい]。なぜなら[購入したい商品をまとめて決済したい]から。

## 背景・目的

この機能は以下の課題・目的を解決するために必要です。

- (この機能が必要な背景や目的を記述する)

## 受け入れ条件（完了の定義）

- [ ] (具体的な完了条件1)
- [ ] (具体的な完了条件2)
- [ ] (具体的な完了条件3)

## 技術的考慮事項

- (技術的に考慮すべき点1)
- (技術的に考慮すべき点2)

## 依存関係・ブロッカー

- (依存しているIssueや外部要因など)
- (依存しているIssueや外部要因など)

## 関連資料・Issue

- (関連するドキュメントやIssueや資料)
- (関連するドキュメントやIssueや資料)
```

## Backlog Example

```
## ユーザーストーリー

ログイン済みのユーザーとして、お気に入りボタンを使って商品を保存したい。なぜなら、あとで比較・購入しやすくなるから。

## 背景・目的

- ユーザーが購入を即決せずに検討することが多いため、再訪時の利便性を高めたい  
- 商品ページの離脱率が高く、検討中のユーザーを取りこぼしている可能性がある

## 受け入れ条件（完了の定義）

- [ ] 商品カードまたは詳細ページに「♡」ボタンが表示されている  
- [ ] ボタンを押すと商品がお気に入りリストに追加される  
- [ ] 再度押すとお気に入りから削除される  
- [ ] ログインユーザーごとにお気に入りが保持される  
- [ ] お気に入り一覧ページが存在し、追加した商品が表示される

## 技術的考慮事項

- ログインユーザーのIDに紐づくお気に入りテーブルを新設  
- フロントエンドはVueでリアクティブに状態変更を反映する  
- バックエンドはAPI経由で追加／削除／取得を非同期処理  
- テストはお気に入り追加／削除／一覧表示のパターンをカバー

## 依存関係・ブロッカー

- #100 ユーザー認証の安定化  
- #102 商品一覧コンポーネントの再設計

## 関連資料・Issue

- デザインFigma: https://figma.com/file/abc1234/favorite-feature  
- 要件定義: `@docs/business/favorite-feature.md`  
- 関連Issue: #90, #103
```
