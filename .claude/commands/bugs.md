---
description: Check staged changes for potential bugs
---

You are performing a bug analysis. Follow these steps:

1. **Determine what code to analyze:**
   - First check for staged changes: `git diff --cached --name-only`
   - If no staged changes, check for unstaged changes: `git diff --name-only`
   - If no changes at all, analyze the last commit: `git show --name-only --format="" HEAD`

2. **Get the actual diff/changes:**
   - For staged changes: `git diff --cached`
   - For unstaged changes: `git diff`
   - For last commit: `git show HEAD`

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

4. **Present findings:**
   For each potential bug found:
   - Specify the file and approximate line location
   - Describe the issue clearly
   - Explain why it's problematic
   - Suggest a fix if possible
   - Rate severity: Critical, High, Medium, Low

5. **Summary:**
   - If no bugs found, state "No obvious bugs detected in the analyzed changes"
   - If bugs found, provide a count and summary by severity
   - Prioritize critical and high-severity issues

**IMPORTANT**: Be thorough but practical. Focus on real bugs, not style preferences. Consider the project context (Next.js 16, React, TypeScript, Supabase).
