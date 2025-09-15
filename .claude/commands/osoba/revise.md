---
allowed-tools: TodoRead, TodoWrite, Bash, Read, Write, Edit, MultiEdit, Grep, Glob, LS
description: "Revise implementation based on review feedback"
---

## Overview

You are a skilled developer responsible for addressing review feedback and fixing issues found during the code review process.  
In this phase, you will review the PR comments, understand the feedback, make necessary corrections, and ensure the implementation meets all quality standards.

---

## Prerequisites

### Documents

Refer to the following documentation:

- **Coding Standards**: @docs/development/coding-standards.md
- **Testing Strategy**: @docs/development/testing-strategy.md
- **Other Development Documents**: @docs/development/INDEX.md

### Expected state of the Issue

- A Pull Request exists with review comments
- The PR has "status:requires-changes" label
- Acceptance criteria remain unchanged

---

## Rules

1. Always read and understand ALL review comments before making changes
2. Address each review comment systematically
3. Follow TDD when adding or modifying tests
4. Respect the existing design and architecture
5. After addressing all feedback, the PR should be ready for re-review
6. Update the Issue label to "status:review-requested" when complete
7. If the current directory is under `.git/osoba/`, this is a dedicated codebase created using git worktree
8. **Work carefully and thoroughly until all issues are resolved, without worrying about time constraints or context compression**
9. **Code Collective Ownership**: Take responsibility for the entire codebase and proactively fix issues even if they seem unrelated to your changes
10. **Time Constraints**: Do not fear time constraints or context compression. Work calmly and thoroughly, prioritizing quality above speed

---

## Instructions

### **⚠️ CI Success is Mandatory ⚠️**

**Passing CI is an absolute prerequisite for task completion.**

- Even if CI failures are "unrelated to your current changes", **you must make every effort to fix those issues**
- All CI problems must be resolved, including test failures, build errors, and lint errors
- Never mark a task as complete while CI is failing

### Workflow (Overview)

1. Check the PR and review comments
2. Understand all feedback points
3. Make necessary corrections
4. Run tests to verify fixes
5. **Ensure CI passes completely**
6. Commit changes with clear messages
7. Post a summary of changes made
8. Update Issue labels

---

## Detailed Steps

1. **Check the Pull Request and review comments**
   - Run `gh pr list --author @me --state open` to find your PR
   - Run `gh pr view <PR number>` to see PR details
   - Run `gh pr view <PR number> --comments` to read all review comments
   - Make a list of all feedback points that need to be addressed

2. **Understand the feedback**
   - Categorize feedback into:
     - Code quality issues
     - Bug fixes
     - Test coverage gaps
     - Documentation updates
     - Style/formatting issues
   - Prioritize critical issues first

3. **Make corrections systematically**
   - Address each feedback point one by one
   - Write/update tests as needed
   - Ensure each change maintains backward compatibility
   - Commit frequently with descriptive messages like:
     ```
     fix: address review feedback on error handling
     refactor: improve variable naming as suggested
     test: add missing test cases for edge conditions
     ```

4. **Run tests and verify (MANDATORY)**
   - **⚠️ CRITICAL: All tests in the entire codebase must pass - this is an absolute requirement for acceptance**
   - Run the full test suite (`bin/rails spec` - NO ARGUMENTS) to ensure nothing is broken # timeout 600000ms
   - **ABSOLUTE REQUIREMENT**: Never mark as complete without running the full test suite
   - Verify that all review points have been addressed
   - Check that the code still meets the original requirements
   - **Ensure CI passes completely**
   - If CI fails, fix the issues regardless of their cause
   - **IMPORTANT**: Execute `bin/rails spec` without any arguments to test the entire codebase

5. **Post a summary comment**
   - Create a comment on the PR summarizing what was changed:
   ```bash
   gh pr comment <PR number> --body "## レビュー指摘対応完了

   以下の指摘事項に対応しました：
   - ✅ [対応した項目1]
   - ✅ [対応した項目2]
   - ✅ [対応した項目3]

   全てのテストがパスすることを確認済みです。
   再レビューをお願いいたします。"
   ```

6. **Update Issue labels**
   - Remove "status:revising" label
   - Add "status:review-requested" label
   ```bash
   gh issue edit <issue number> \
     --remove-label "status:revising" \
     --add-label "status:review-requested"
   ```

---

## Common Review Feedback Types

### Code Quality
- Variable/function naming improvements
- Code duplication removal
- Complex logic simplification
- Error handling improvements

### Testing
- Missing test cases
- Edge case coverage
- Test data improvements
- Mock simplification

### Documentation
- Missing or unclear comments
- API documentation updates
- README updates

### Performance
- Inefficient algorithms
- Unnecessary database queries
- Memory leak risks

---

## Best Practices

1. **Be thorough**: Address ALL feedback, not just the easy ones
2. **Be communicative**: If you disagree with feedback, explain why
3. **Be proactive**: Look for similar issues elsewhere in the code
4. **Be respectful**: Thank reviewers for their feedback
5. **Be complete**: Ensure all tests pass before marking as ready

---

## Important Notes

- **Never mark as "ready for review" if CI is failing**
- **If CI is failing, you must attempt to fix it even if the cause is unrelated to your current changes**
- If you cannot address certain feedback, explain why in the PR comments
- Keep the commit history clean and meaningful
- Always verify the changes work as expected before updating labels
- **Task completion requirement: CI must pass completely**
- **CRITICAL: Always update Issue labels upon task completion, regardless of any circumstances. This is an essential rule to keep the workflow moving forward without interruption.**