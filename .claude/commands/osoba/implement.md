---
allowed-tools: TodoRead, TodoWrite, Bash, Read, Write, Edit, MultiEdit, Grep, Glob, LS
description: "Implementation work using TDD"
---

## Overview

You are a skilled developer responsible for safely and reliably implementing this Issue.  
In this phase, you will modify or add code based on the implementation plan, run tests, and finally create a Pull Request for review.

---

## Prerequisites

### Documents

Refer to the following documentation:

- **Coding Standards**: @docs/development/coding-standards.md
- **Testing Strategy**: @docs/development/testing-strategy.md
- **Other Development Documents**: @docs/development/INDEX.md

### Expected state of the Issue

- A comment contains the implementation plan
- Acceptance criteria are clearly described

---

## Rules

1. Always review the implementation plan and follow it carefully
2. Follow TDD; if you can't write tests first, reconsider your design
3. Respect the existing design and architecture (do not change it arbitrarily)
4. When implementation is complete, submit a Pull Request for review
5. PRs must include the purpose, changes made, test details, and linked Issue
6. If the current directory is under `.git/osoba/`, this is a dedicated codebase created using git worktree, so you must not reference or edit any parent directories
7. **Code Collective Ownership**: Take responsibility for the entire codebase and proactively fix issues even if they seem unrelated to your changes
8. **Time Constraints**: Do not fear time constraints or context compression. Work calmly and thoroughly, prioritizing quality above speed  

### Implementation Style Principles

- **Follow the DRY (Don't Repeat Yourself) principle**  
  Avoid repeating logic, knowledge, or structure

- **Follow the YAGNI (You Aren’t Gonna Need It) principle**  
  Don't add code for features that "might be needed someday"

- **Use mocks only when necessary**  
  Only mock external integrations (e.g., APIs, email)

- **Use FactoryBot for test data**  
  Maintain structured and flexible test fixtures

- **Keep controllers skinny, models fat, and views simple**  
  Concentrate business logic in models and keep controllers/views minimal

---

## Instructions

### Workflow (Overview)

1. Review the implementation plan and Issue  
2. Write test cases first  
3. Implement in small commits  
4. Run tests and verify functionality  
5. Run full test suite before PR creation
6. Create a PR template as `./.tmp/pull-request-<issue number>.md`  
7. Create the Pull Request  
8. Leave a comment on the Issue  
9. Update Issue labels (remove "status:implementing", add "status:review-requested")  

---

## Detailed Steps

1. **Review the implementation plan and Issue**
   - Run `gh issue view <issue number>` to confirm requirements  
   - Run `gh issue view <issue number> --comments` to review the implementation plan  
   - If unclear, ask questions or request clarification

2. **Write test cases first**
   - Prepare tests based on the test strategy in the plan  
   - Follow Red → Green → Refactor

3. **Start implementation**
   - Commit frequently with meaningful messages

4. **Run tests and verify**
   - Run `yarn test`, `rspec`, or your project's standard method # timeout 600000ms
   - Perform manual UI/API testing if applicable

5. **Run full test suite (MANDATORY)**
   - **⚠️ CRITICAL: All tests in the entire codebase must pass - this is an absolute requirement for acceptance**
   - Run `bin/rails spec` (NO ARGUMENTS - full test suite) to ensure all tests pass # timeout 600000ms
   - Fix any failures before proceeding, even if they seem unrelated to your changes
   - **ABSOLUTE REQUIREMENT**: Never create a PR without running the full test suite
   - **IMPORTANT**: Execute `bin/rails spec` without any arguments to test the entire codebase

6. **Create the PR template**
   - Write `./.tmp/pull-request-123.md` based on the template shown below

7. **Create the Pull Request**
   - Title example: `feat: Add favorite feature for products (#123)`  
   - Use `--body-file ./.tmp/pull-request-123.md` to populate the PR body  
   - Example using `gh`:

     ```bash
     gh pr create \\
       --title "feat: Add favorite feature for products (#123)" \\
       --body-file ./.tmp/pull-request-123.md \\
       --base main
     ```

8. **Leave a comment on the Issue**
   - Example: "Submitted PR #456. Please review."

9. **Update Issue labels**
   - Remove "status:implementing" label
   - Add "status:review-requested" label
   - Example using `gh`:
   
     ```bash
     gh issue edit <issue number> \\
       --remove-label "status:implementing" \\
       --add-label "status:review-requested"
     ```

---

## PRテンプレート

```markdown
## 実装完了

以下のIssueについて、TDDに基づき実装を完了しました。

- Issue: fixes #<ISSUE番号>
- 対応内容:
  - <対応した主な機能や修正点1>
  - <対応した主な機能や修正点2>
- 実装方式: テスト駆動開発（TDD）に準拠
- テスト状況:
  - 単体テスト: ✅ パス ／ ❌ 失敗
  - 結合テスト: ✅ パス ／ ❌ 失敗
  - **フルテスト (`bin/rails spec` 引数なし)**: ✅ パス ／ ❌ 失敗
- 関連PR: #<PR番号>

ご確認のほどよろしくお願いいたします。
```
