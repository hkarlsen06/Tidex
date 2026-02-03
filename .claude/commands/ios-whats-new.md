---
description: Generate iOS "What's New" text in English and Norwegian from commits since last release
---

Generate App Store "What's New" release notes in both English and Norwegian based on commits since the last published iOS version, and update the metadata source file.

## Input

The argument `$ARGUMENTS` is the git reference (tag, commit hash, or marker) of the last published iOS version. If not provided, prompt the user for it.

## Process

1. **Get commits since the reference:**
   ```bash
   git log $ARGUMENTS..HEAD --oneline
   ```

2. **Get detailed changes for iOS-related commits:**
   ```bash
   git log $ARGUMENTS..HEAD --stat -- ios/
   ```
   Also check for relevant Next.js API changes that affect the iOS app:
   ```bash
   git log $ARGUMENTS..HEAD --stat -- app/api/
   ```

3. **Categorize changes into two groups:**

   **User-facing (list individually):**
   - New features users can see or interact with
   - Bug fixes that affected user experience
   - Noticeable performance improvements
   - UI/UX changes users will notice

   **Non-user-facing (consolidate into one line):**
   - Internal refactoring
   - Code cleanup
   - Developer tooling changes
   - Test-only changes
   - Minor performance tweaks
   - Backend/API changes users won't notice
   - Dependency updates

4. **Consolidation rule:**
   If there are non-user-facing changes, add ONE generic line at the end:
   - English: "- Bug fixes and other improvements"
   - Norwegian: "- Feilrettinger og andre forbedringer"

   Do NOT list technical details users wouldn't understand or care about.

## Output

1. **Update the metadata source file** at `ios/Scripts/appstore-metadata-source.json`:
   - Update `metadata.en.release_notes` with English release notes
   - Update `metadata.nb.release_notes` with Norwegian release notes
   - Use the Edit tool to modify only the `release_notes` fields

2. **Show the user** what was written (for review)

## Guidelines

- **Keep it concise:** App Store limits "What's New" to 4000 characters
- **Focus on benefits:** Describe what the user gains, not technical details
- **Use simple language:** Avoid jargon and technical terms
- **Start with the most important change**
- **Use bullet points:** Start each line with a hyphen (-)
- **Use consistent formatting:** Start each bullet with a verb (Added, Fixed, Improved, etc.)
- **Norwegian translation:** Use natural Norwegian Bokmål, not literal translation

## Release Notes Format

Use this format for the release_notes field (plain text with line breaks):

```
- First improvement or feature
- Second improvement or fix
- Third item
```

## Examples

### English
```
- Added shift reminders with customizable notification times
- Fixed an issue where overnight shifts displayed incorrect hours
- Bug fixes and other improvements
```

### Norwegian (Bokmål)
```
- Lagt til vaktpåminnelser med tilpassbare varslingstider
- Rettet en feil der nattevakter viste feil antall timer
- Feilrettinger og andre forbedringer
```

### What NOT to include as separate items:
- "Refactored authentication module" → consolidate
- "Updated dependencies" → consolidate
- "Improved code organization" → consolidate
- "Fixed memory leak in background task" → consolidate (unless it caused visible issues)
- "Added analytics tracking" → consolidate

## After Updating

Remind the user they can now run:
```bash
cd ios && npm run generate-metadata
```
This will regenerate all localized metadata files, translating the new release notes to all supported languages.

## Important

- If there are no user-facing changes, set release notes to "Bug fixes and performance improvements." / "Feilrettinger og ytelsesforbedringer."
- If the reference is invalid, ask the user to provide a valid git reference
- Always update both English and Norwegian release notes together
