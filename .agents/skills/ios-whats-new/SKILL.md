---
name: ios-whats-new
description: Generate Tidex iOS App Store "What's New" release notes in English and Norwegian Bokmal from git commits since a provided reference, update `ios/Scripts/appstore-metadata-source.json`, and show the final text for review. Use when asked for iOS release notes, App Store changelog copy, expedited review notes, or "what's new" text based on recent commits.
---

# iOS What's New

Use this skill when the user wants App Store release notes for the Tidex iOS app.

## Inputs

- Expect a git reference for the last published build: tag, commit SHA, branch, or other valid ref.
- If the reference is missing, ask for it before generating notes.
- If the user provides extra context about what to emphasize, use it as editorial guidance and verify it against the recent changes.

## Review The Change Set

From the repo root, inspect the commits since the reference:

```bash
git log <ref>..HEAD --oneline -- ios/ supabase/
git log <ref>..HEAD --stat -- ios/ supabase/
git diff --name-only <ref>..HEAD -- ios/ supabase/
```

Focus primarily on `ios/`. Include `supabase/` changes only when they materially affect iOS behavior, such as auth, purchases, sync, notifications, messaging, or other user-visible app behavior.

## Decide What Belongs In Release Notes

Split changes into two buckets:

- User-facing: features, fixes, performance wins, UX changes, or reliability improvements users will notice.
- Non-user-facing: refactors, cleanup, dependency bumps, internal tooling, tests, or backend changes without a visible effect.

Rules:

- List user-facing items individually.
- Collapse non-user-facing work into one final generic line.
- Do not expose technical implementation details.
- Put the most important user benefit first.
- If the user wants expedited review messaging, lead with the critical bug fix or reliability issue they need to highlight.

## Writing Rules

- Write both English and Norwegian Bokmal release notes together.
- Keep each line as a `-` bullet in plain text.
- Start bullets with a clear action verb such as `Added`, `Fixed`, `Improved`, `Lagt til`, `Rettet`, or `Forbedret`.
- Use simple user-facing language, not engineering jargon.
- Keep the total comfortably under the App Store `release_notes` limit of 4000 characters.
- Use natural Norwegian Bokmal, not a literal translation.

Default consolidation line:

- English: `- Bug fixes and other improvements`
- Norwegian: `- Feilrettinger og andre forbedringer`

If there are no clear user-facing changes, use:

- English: `Bug fixes and performance improvements.`
- Norwegian: `Feilrettinger og ytelsesforbedringer.`

## Update The Metadata Source

Unless the user explicitly asks for draft-only output, update:

- `ios/Scripts/appstore-metadata-source.json`

Modify only:

- `metadata.en.release_notes`
- `metadata.nb.release_notes`

Do not rewrite unrelated metadata fields.

## Final Response

After updating the source file:

- Show the English and Norwegian release notes that were written.
- Mention the reference used to generate them.
- Remind the user they can regenerate localized App Store metadata with:

```bash
pnpm --dir ios generate-metadata
```
