# Review Changes and Update Documentation

You are conducting a comprehensive code review of all changes since departure from origin. Follow these steps in order:

## Step 1: Identify Changes

First, determine what has changed:
1. Run `git fetch origin` to update remote references
2. Run `git log origin/main..HEAD --oneline` to see commits ahead of origin
3. Run `git diff origin/main...HEAD --stat` to see file changes summary
4. Run `git diff origin/main...HEAD` to see full diff of changes

## Step 2: Analyze Changes

Review the changes and understand:
- What features were added or modified
- What files were changed and why
- What architectural or structural changes were made
- What configuration changes were made
- What dependencies were added/updated

## Step 3: Update CLAUDE.md

Based on the changes you found:
1. Read the current CLAUDE.md file
2. Update it to accurately reflect:
   - New routes or pages added
   - New components or architectural patterns
   - New configuration or environment variables
   - New commands or scripts
   - Changes to key principles or patterns
   - New features or functionality
3. Keep the existing structure and style
4. Only update sections that are affected by the changes
5. Use the Edit tool to make the updates

## Step 4: Bug Detection

Analyze the changes for potential bugs:
- Type errors or TypeScript issues
- Logic errors or edge cases
- Missing error handling
- Incorrect imports or dependencies
- Authentication/authorization issues
- Race conditions or async issues
- Missing translations for i18n
- Hardcoded values that should be configurable
- Violations of project principles (e.g., importing from components/ui instead of components/app)
- Theme/styling issues (hardcoded colors instead of semantic tokens)
- Server/client component boundary issues

## Step 5: Bug Handling

### If NO bugs found:
- Report that no bugs were detected
- Summarize what was reviewed
- Suggest the user run tests if applicable

### If bugs found:

First, classify each bug as either SIMPLE or COMPLEX:

**Simple bugs** (can be fixed with straightforward edits):
- Import statement fixes
- Type annotation fixes
- Simple logic corrections (single condition, one-line fixes)
- Missing null checks
- Hardcoded color replacements with semantic tokens
- Missing await keywords
- Incorrect variable references
- Simple prop passing issues

**Complex bugs** (require deeper changes or careful consideration):
- Architectural issues
- Race conditions
- Complex logic errors requiring multiple file changes or refactoring
- Breaking changes
- Authentication/security issues
- Database schema or query issues
- State management problems spanning multiple components

Then decide on the action:

### If ALL bugs are SIMPLE (regardless of count):
1. Fix them all automatically using the Edit tool
2. Explain what was fixed for each bug
3. Suggest to the user: "Please test the changes and run /smart-push when ready"

### If ANY bug is COMPLEX or if there are too many simple bugs to fix confidently in one pass:
1. Get the unsynced commit hashes: `git log origin/main..HEAD --format="%H"`
2. Create a file named `bugs-[YYYY-MM-DD].md` in the project root with:
   - First line: The commit hashes that aren't synced (space-separated)
   - Detailed bug report in markdown format including:
     - Description of each bug
     - Location (file and line numbers)
     - Severity (high/medium/low)
     - Classification (simple/complex)
     - Suggested fix approach
3. Inform the user about the bugs file and recommend addressing them before pushing

**Use your judgment**: If you're confident you can fix all the bugs correctly in one pass, do it. If you have any doubt or if the fixes require careful consideration of business logic, create the bugs file instead.

## Important Notes

- Be thorough but concise
- Focus on actual bugs, not style preferences
- Consider the project's architecture and principles from CLAUDE.md
- Use the TodoWrite tool to track your progress through these steps
- Always provide the user with actionable next steps
