---
allowed-tools: Bash, Read, Write, Edit, MultiEdit, Grep, Glob, LS
description: "Review and merge a Pull Request"
---

# Review Plan

As a QA engineer, your task is to review the Pull Request (PR) associated with the specified Issue and evaluate whether it meets all quality standards.

## Context

- Specification Driven Development: @.claude/osoba/docs/spacification_driven_development.md
- Target Issue number: $ARGUMENTS


## Workflow

### 1. Check the Issue

- Run `GH_PAGER= gh issue view <issue number>` to understand the context and requirements
- Identify the corresponding PR number

- Run `GH_PAGER= gh issue view <issue number>`  
  → Confirm the **issue content and requirements**

- Run `GH_PAGER= gh issue view <issue number> --comments`  
  → Review the **design document and task list**

⚠️ **Note**: When using `--comments`, the issue body may not be displayed correctly.  
Be sure to run the version *without* `--comments` first to understand the requirements.

### 2. Check the PR

- Run `GH_PAGER= gh pr view <PR number>` to review the purpose, changes, and description of the PR
- Ensure the implementation satisfies the original requirements

### 3. Check for Conflicts

- Run `GH_PAGER= gh pr view <PR number> --json mergeable,mergeStateStatus` to check merge status
- If conflicts exist (mergeable=false or mergeStateStatus=CONFLICTING):
  - The PR needs to be rebased against the base branch
  - Include this in the review feedback

### 4. Review Code Changes

- Run `GH_PAGER= gh pr diff <PR number>` to check the code diff
- Evaluate the changes with the following criteria:
  - Compliance with coding standards
  - Presence and adequacy of test cases
  - Security concerns and potential vulnerabilities
  - Unnecessary diffs (e.g., debug code, commented-out lines)

### 5. Check CI Results (MANDATORY - MUST WAIT FOR COMPLETION)

- **⚠️ CRITICAL: You MUST wait for CI to complete before providing review results**
- **NEVER provide review results while CI is still running or pending**
- Run `GH_PAGER= gh pr checks <PR number>` to verify CI status
  - All checks must ✅ pass
  - If checks are still running, wait and retry until completed
  - ⚠️ **Note**: CI can take over 5 minutes to complete. Be patient and ensure all checks are fully finished before proceeding
  - To wait for CI completion, you can use:
    ```bash
    gh pr checks <PR number> --watch # timeout 600000ms
    ```
    or repeatedly check status:
    ```bash
    while true; do
      gh pr checks <PR number>
      sleep 30
    done # timeout 600000ms
    ```
  - **ABSOLUTE REQUIREMENT**: CI completion, merge capability check, and code review ALL must be complete before providing review results

### 6. Post Review Result (ONLY AFTER CI COMPLETION)

- **⚠️ PREREQUISITE**: Only proceed if ALL of the following are complete:
  1. CI has fully completed (not pending or running)
  2. Merge capability has been verified
  3. Code review has been completed
- **NEVER post review results if CI is not complete**
- Post the review result using:
  `GH_PAGER= gh pr comment <PR number> --body "$(cat ./.tmp/review-result-<issue number>.md)"`
- Use the following template for `./.tmp/review-result-<issue number>.md`:

```markdown
## Review Result

- Issue: #<issue number>
- PR: #<PR number>

### ✅ Verdict
- [ ] Approved (LGTM)
- [ ] Requires changes

### 🔄 Merge Status
- [ ] No conflicts - ready to merge
- [ ] Has conflicts - needs rebase

### 👍 Positive Notes
- [List of strengths in the implementation]

### 🛠 Suggestions for Improvement
- [List of specific recommendations]

### 🔍 Additional Notes
- [Optional remarks if any]
```

### 7. Update Labels

After posting the review result, update the labels based on the verdict:

#### If Approved (LGTM):
1. Keep `status:reviewing` label on the Issue (Issue lifecycle ends here)
2. Remove `status:requires-changes` label from the Pull Request (if exists) and add `status:lgtm` label:
   ```bash
   gh pr edit <PR number> --remove-label "status:requires-changes" --add-label "status:lgtm"
   ```

#### If Requires Changes:
1. Keep `status:reviewing` label on the Issue (Issue remains in review state)
2. Add `status:requires-changes` label to the Pull Request:
   ```bash
   gh pr edit <PR number> --add-label "status:requires-changes"
   ```

## Basic Rules

- Ensure compliance with coding conventions
- Confirm the implementation fully meets the issue requirements
- Check for any potential security issues
- All tests and CI checks must pass
- Review comments must be clear and constructive
