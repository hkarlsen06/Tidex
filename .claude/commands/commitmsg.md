---
description: Generate a commit message based on staged or unstaged changes
---

Analyze the git changes and generate a concise, descriptive commit message following these rules:

1. Run `git diff --cached --stat` to check for staged changes
2. If no staged changes, run `git diff --stat` for unstaged changes
3. Run the appropriate `git diff` (with or without --cached) to see the actual changes
4. Analyze the changes and create a commit message that:
   - Uses imperative mood (e.g., "fix", "add", "remove", not "fixed", "added")
   - Summarizes the main change in one clear line
   - Is concise but descriptive
   - Groups related changes logically

5. Present the commit message in a code block so the user can easily copy it
6. DO NOT create the commit - only generate the message for the user to review and use
