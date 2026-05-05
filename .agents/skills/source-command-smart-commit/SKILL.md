---
name: "source-command-smart-commit"
description: "Analyze changes, generate commit message, and create the commit"
---

# source-command-smart-commit

Use this skill when the user asks to run the migrated source command `smart-commit`.

## Command Template

Analyze the git changes, generate a commit message, and create the commit following these rules:

1. Run `git diff --cached --stat` to check for staged changes
2. If no staged changes, stage all unstaged changes (`git add -A`) and continue
3. Run `git diff --cached` to see the actual staged changes
4. Analyze the changes and create a commit message that:

   - Uses imperative mood (e.g., "fix", "add", "remove", not "fixed", "added")
   - Summarizes the main change in one clear line
   - Is concise but descriptive
   - Groups related changes logically
   - DOES NOT include the Codex footer.
5. Create the commit using the generated message
6. Show the commit summary and SHA to confirm success
