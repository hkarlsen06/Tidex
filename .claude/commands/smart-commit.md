---
description: Analyze changes, generate commit message, and create the commit
---

Analyze the git changes, generate a commit message, and create the commit following these rules:

1. Run `git diff --cached --stat` to check for staged changes
2. If no staged changes, inform the user and stop - do NOT stage files automatically
3. Run `git diff --cached` to see the actual staged changes
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

5. Create the commit using the generated message
6. Show the commit summary and SHA to confirm success

IMPORTANT: NEVER stage unstaged files. Only commit what the user has explicitly staged.

IMPORTANT: This command WILL create the commit automatically. Use `/commit-summary` if you only want to see the message first.
