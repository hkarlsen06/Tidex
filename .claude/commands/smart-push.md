---
description: Analyze changes, commit, and push to remote repository
---

Analyze the git changes, create a commit, and push to the remote repository following these rules:

1. Run `git diff --cached --stat` to check for staged changes
2. If no staged changes, run `git diff --stat` for unstaged changes
3. If no changes at all (clean working tree), check for unpushed commits using `git log @{u}.. --oneline`
   - If there are unpushed commits, run lint and build checks, then push them
   - Show the commits that will be pushed before pushing
4. Run the appropriate `git diff` (with or without --cached) to see the actual changes
5. Analyze the changes and create a commit message that:
   - Uses imperative mood (e.g., "fix", "add", "remove", not "fixed", "added")
   - Summarizes the main change in one clear line
   - Is concise but descriptive
   - Groups related changes logically
   - Includes the Claude Code footer:
     ```
     🤖 Generated with [Claude Code](https://claude.com/claude-code)

     Co-Authored-By: Claude <noreply@anthropic.com>
     ```

6. Stage all changes if nothing is staged (using `git add .`)
7. Create the commit using the generated message
8. Run `pnpm run lint` to check for linting errors
9. Run `pnpm run build` to verify the build succeeds
11. If lint or build fails:
   - Show the errors to the user
   - Do NOT push to remote
   - Explain that the commit was created but not pushed due to errors
   - Suggest fixing the issues before pushing manually or running `/smart-push` again
12. If lint and build pass, push to the remote repository (using `git push`)
13. Show the commit summary, SHA, and push result to confirm success

IMPORTANT: This command WILL create the commit AND push to remote automatically. Use `/smart-commit` if you don't want to push yet, or `/commit-summary` if you only want to see the message first.

SAFETY CHECK: Before pushing, verify:
- You're not on the main/master branch (unless explicitly intended)
- The changes are ready to be shared with the team
- No sensitive information is being committed
