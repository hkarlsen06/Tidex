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

2. **Categorize the changed files:**
   - **iOS/Swift files**: Files in `ios/` directory or with `.swift` extension
   - **Next.js/Web files**: All other files (TypeScript, JavaScript, CSS, etc.)
   - Note which categories have changes for steps 4-5

3. **Get the actual diff/changes:**

   - For staged changes: `git diff --cached`
   - For unstaged changes: `git diff`
   - For unpushed commits (when working tree is clean): `git diff @{u}..HEAD`
   - For last commit (when no unpushed commits): `git show HEAD`

4. **Analyze the code for potential bugs:**
   Review the changes looking for:

   **For all code:**
   - Logic errors (off-by-one, incorrect conditionals, wrong operators)
   - Null/undefined/nil reference issues
   - Type mismatches or unsafe type assertions
   - Missing error handling or edge cases
   - Race conditions or timing issues
   - Breaking API changes or contract violations
   - Security issues (XSS, injection, exposed secrets)

   **For TypeScript/JavaScript (Next.js):**
   - Async/await issues (missing await, unhandled promises)
   - React-specific issues (missing dependencies, incorrect hooks usage, state mutation)
   - Memory leaks (event listeners not cleaned up, unclosed resources)
   - Performance issues (unnecessary re-renders, inefficient loops)
   - Incorrect imports or missing dependencies

   **For Swift (iOS):**
   - Memory management issues (retain cycles, missing weak/unowned)
   - MainActor/concurrency violations
   - Force unwrapping that could crash
   - Missing @Published or observation issues
   - Incorrect use of async/await or Task
   - SwiftUI view update issues (non-reactive property access)

5. **Run linters (only for changed file types):**

   **If iOS/Swift files changed:**
   - Run SwiftLint: `swiftlint lint --quiet ios/App/TidexApp/Native`
   - Report any warnings or errors related to the changed files (filter output to only show issues in changed files)
   - Note: Do NOT attempt to build or run Xcode - just lint

   **If Next.js/Web files changed:**
   - Run `pnpm lint` to check for linting issues
   - Fix any linting errors that are related to the changed files
   - Report any issues that couldn't be auto-fixed

   **If ONLY iOS files changed (no Next.js files):**
   - Skip `pnpm lint` and `pnpm test` entirely

6. **Run tests (only if Next.js files changed):**

   **If Next.js/Web files changed:**
   - Run `pnpm test` to execute the test suite
   - If tests fail, analyze whether the failures are related to the changes
   - Fix any test failures caused by the changes
   - Report test results summary

   **If ONLY iOS files changed:**
   - Skip `pnpm test` (iOS tests require Xcode)

7. Perform fixes for any findings from steps 4-6

8. **Summary:**

   - If no bugs found, state "No obvious bugs detected in the analyzed changes"
   - If bugs found, provide a count and summary by severity
   - Prioritize critical and high-severity issues

**IMPORTANT**: Be thorough but practical. Focus on real bugs, not style preferences. Consider the project context (Next.js 16, React, TypeScript, Supabase for web; SwiftUI, iOS 26 for mobile).
