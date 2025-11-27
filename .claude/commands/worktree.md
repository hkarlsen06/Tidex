---
description: Create a git worktree for feature development
---

Create a git worktree for feature development following the project's worktree workflow.

## Steps

1. **Check current branch:**
   ```bash
   git branch --show-current
   ```

2. **If NOT on main:**
   - Inform the user they're already on a feature branch
   - Ask if they want to continue working on the current branch or create a new worktree anyway
   - If they want to stay, stop here

3. **If on main (or user wants a new worktree):**
   - Ask the user: "What feature or task are you planning to work on?"
   - Wait for their response to understand the scope

4. **Based on their response:**
   - Generate a descriptive kebab-case name for the branch (e.g., `add-dark-mode`, `fix-auth-flow`, `refactor-payroll`)
   - Create the worktree:
     ```bash
     git worktree add ../tidex-claude-<descriptive-name> -b claude/<descriptive-name>
     ```

5. **Change to the worktree:**
   ```bash
   cd ../tidex-claude-<descriptive-name>
   ```

6. **Copy environment files** (worktrees don't share untracked files):
   ```bash
   cp ../tidex/.env.local .env.local
   ```

7. **Install dependencies:**
   ```bash
   npm install
   ```

8. **Confirm to the user:**
   - Let them know the worktree is ready
   - Show the branch name and directory path
   - Remind them that when done, they can create a PR to merge back to main

## Important Notes

- Branch naming convention: `claude/<descriptive-name>`
- Worktree directory: `../tidex-claude-<descriptive-name>` (sibling to main repo)
- Always copy `.env.local` since worktrees don't share untracked files
- Always install dependencies since worktrees don't share node_modules
- Keep the branch name short but descriptive
