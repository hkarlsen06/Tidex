---
description: Generate iOS "What's New" text in English and Norwegian from commits since last release
---

Generate App Store "What's New" release notes in both English and Norwegian based on commits since the last published iOS version.

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

3. **Analyze the changes** focusing on:
   - New features visible to users
   - Bug fixes that improve user experience
   - Performance improvements
   - UI/UX enhancements
   - Any breaking changes or important notes

4. **Filter out non-user-facing changes:**
   - Internal refactoring
   - Code cleanup
   - Developer tooling changes
   - Test-only changes

## Output Format

Generate the release notes in this exact format:

```
## English

[2-4 bullet points describing user-facing changes in clear, simple language]

---

## Norsk

[Same bullet points translated to Norwegian Bokmål]
```

## Guidelines

- **Keep it concise:** App Store limits "What's New" to 4000 characters
- **Focus on benefits:** Describe what the user gains, not technical details
- **Use simple language:** Avoid jargon and technical terms
- **Start with the most important change**
- **Use consistent formatting:** Start each bullet with a verb (Added, Fixed, Improved, etc.)
- **Norwegian translation:** Use natural Norwegian Bokmål, not literal translation

## Examples

### English
- Added shift reminders with customizable notification times
- Fixed an issue where overnight shifts displayed incorrect hours
- Improved dashboard loading performance
- Updated design for better accessibility

### Norsk
- Lagt til vaktpåminnelser med tilpassbare varslingstider
- Rettet en feil der nattevakter viste feil antall timer
- Forbedret lastetiden for dashbordet
- Oppdatert design for bedre tilgjengelighet

## Important

- If there are no user-facing changes, indicate this clearly
- If the reference is invalid, ask the user to provide a valid git reference
- Present both languages clearly separated for easy copy-paste to App Store Connect
