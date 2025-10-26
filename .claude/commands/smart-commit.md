---
description: Analyze changes, generate commit message, and create the commit
---

Analyze the git changes, generate a commit message, and create the commit following these rules:

1. Run `git diff --cached --stat` to check for staged changes
2. If no staged changes, run `git diff --stat` for unstaged changes
3. Run the appropriate `git diff` (with or without --cached) to see the actual changes
4. Analyze the changes and create a commit message that:
   - Uses imperative mood (e.g., "fix", "add", "remove", not "fixed", "added")
   - Summarizes the main change in one clear line
   - Is concise but descriptive
   - Groups related changes logically
   - Includes the Claude Code footer:
     ```
     🤖 Generated with [Claude Code](https://claude.com/claude-code)

     Co-Authored-By: Claude <noreply@anthropic.com>
     ```

5. Stage all changes if nothing is staged (using `git add .`)
6. Create the commit using the generated message
7. Show the commit summary and SHA to confirm success

IMPORTANT: This command WILL create the commit automatically. Use `/commit-summary` if you only want to see the message first.
