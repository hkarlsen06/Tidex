# Cherry-pick to Remote Branch

Cherry-pick commits to another branch (e.g., main) without switching from your current branch.

**Primary use case:** Push API/backend updates to production (main) while working on the iOS branch, without including iOS-specific changes.

## Usage

```
/cherry-pick-remote [commit] [target-branch]
```

**Arguments:**
- `commit` - Commit hash or reference (default: HEAD)
- `target-branch` - Target branch name (default: main)

## Examples

```
/cherry-pick-remote              # Cherry-pick HEAD to main
/cherry-pick-remote abc123       # Cherry-pick specific commit to main
/cherry-pick-remote HEAD~2 dev   # Cherry-pick 2 commits back to dev branch
```

## Instructions

When this skill is invoked, follow these steps:

1. **Parse arguments**: Extract commit ref and target branch from args. Defaults: commit=HEAD, target=main

2. **CRITICAL: Check for iOS changes**:
   ```bash
   git diff-tree --no-commit-id --name-only -r <commit> | grep -E "^ios/"
   ```

   **If the commit contains ANY changes in the `ios/` directory:**
   - STOP and warn the user: "This commit contains iOS directory changes which should not be cherry-picked to main."
   - List the iOS files that would be included
   - Ask the user to either:
     a) Create a new commit with only the API/backend changes
     b) Confirm they really want to proceed (rare edge case)
   - Do NOT proceed without explicit user confirmation

3. **Show what will be cherry-picked** (only non-iOS files):
   ```bash
   git log --oneline -1 <commit>
   git diff-tree --no-commit-id --name-only -r <commit>
   ```

4. **Clean up any existing worktree**:
   ```bash
   git worktree remove /tmp/cherry-pick-worktree --force 2>/dev/null || true
   ```

5. **Create temporary worktree**:
   ```bash
   git fetch origin <target-branch>
   git worktree add /tmp/cherry-pick-worktree <target-branch>
   ```

6. **Cherry-pick in worktree**:
   ```bash
   cd /tmp/cherry-pick-worktree && git cherry-pick <commit>
   ```

7. **Handle conflicts**: If there are conflicts:
   - Show the user what files conflict
   - Ask if they want to:
     a) Resolve by keeping only specific files (exclude files that don't exist on target)
     b) Abort the cherry-pick
   - For files that don't exist on target branch, use `git rm <file>`
   - For modified files to keep, use `git add <file>`
   - Then commit with: `git commit --no-edit`

8. **Push to remote**:
   ```bash
   cd /tmp/cherry-pick-worktree && git push origin <target-branch>
   ```

9. **Cleanup worktree**:
   ```bash
   git worktree remove /tmp/cherry-pick-worktree
   ```

10. **Report result**: Show the commit hash that was pushed to the target branch and confirm success.

## Error Handling

- If worktree already exists, remove it first with `--force`
- If push is rejected, the worktree approach handles this since it checks out the latest target branch
- Always clean up the worktree, even on failure
- If cherry-pick fails completely, abort and clean up:
  ```bash
  cd /tmp/cherry-pick-worktree && git cherry-pick --abort
  git worktree remove /tmp/cherry-pick-worktree --force
  ```
