---
description: Check staged changes for potential bugs
---

You are performing a bug analysis. Follow these steps:

1. **Determine what code to analyze:**

   - First check for staged changes: `git diff --cached --name-only`
   - If no staged changes, check for unstaged changes: `git diff --name-only`
   - If no changes at all (clean working tree):
     - Check if there are unpushed commits: `git rev-list @{u}..HEAD --count`
     - If unpushed commits exist, analyze all commits since diverging from origin
     - If no unpushed commits, analyze the last commit: `git show --name-only --format="" HEAD`

2. **Get the actual diff/changes:**

   - For staged changes: `git diff --cached`
   - For unstaged changes: `git diff`
   - For unpushed commits (when working tree is clean): `git diff @{u}..HEAD`
   - For last commit (when no unpushed commits): `git show HEAD`

3. **Analyze the code for potential bugs:**
   Review the changes looking for:

   - Logic errors (off-by-one, incorrect conditionals, wrong operators)
   - Null/undefined reference issues
   - Type mismatches or unsafe type assertions
   - Missing error handling or edge cases
   - Async/await issues (missing await, unhandled promises)
   - React-specific issues (missing dependencies, incorrect hooks usage, state mutation)
   - Memory leaks (event listeners not cleaned up, unclosed resources)
   - Race conditions or timing issues
   - Incorrect imports or missing dependencies
   - Breaking API changes or contract violations
   - Performance issues (unnecessary re-renders, inefficient loops)
   - Security issues (XSS, injection, exposed secrets)

4. Perform fixes for findings
5. **Summary:**

   - If no bugs found, state "No obvious bugs detected in the analyzed changes"
   - If bugs found, provide a count and summary by severity
   - Prioritize critical and high-severity issues

**IMPORTANT**: Be thorough but practical. Focus on real bugs, not style preferences. Consider the project context (Next.js 16, React, TypeScript, Supabase).
