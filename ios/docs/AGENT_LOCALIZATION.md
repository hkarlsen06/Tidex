# iOS localization workflow

Commands and paths are relative to the repository root.

## iOS Localization Scripts

Use `./scripts/xcstrings-set` from the repo root for ordinary plain string catalog edits.

**Localization key usage:**

- Always use generated `LocalizedStringResource` symbols in Swift code, for example `Text(.settingsSaveButton)` or `String(localized: .settingsSaveButton)`.
- Never call localization APIs with raw string keys such as `String(localized: "settings.saveButton")`, `Text("settings.saveButton", tableName: "Localizable")`, `LocalizedStringResource("settings.saveButton", table: "Localizable")`, or `NSLocalizedString("settings.saveButton", ...)`.
- If a key has no generated symbol, add or rename the catalog entry to a dot-notation key that does generate one, then use the symbol.

**Commands:**

```bash
./scripts/xcstrings-set ios/Resources/Localization/App/Localizable.xcstrings feature.key \
  --comment "Translator context" \
  --en "English" \
  --nb "Norwegian"
bun run ios:l10n:delete -- --key "feature.key"
bun run ios:l10n:search -- "query"
bun run ios:l10n:audit
bun run ios:l10n:validate
```

- New keys must include English, Norwegian Bokmal, and a translator comment.
- The helper preserves existing catalog order by default to keep diffs focused. Pass `--sort-keys` only when intentionally normalizing a catalog.
- Use `--locale <code>=<value>` for additional languages if a specific non-generated locale edit is needed.
- Use Xcode's String Catalog editor or XLIFF export/import for pluralization, substitutions, device variants, or bulk translator workflows.
- After adding English/Norwegian copy, remind the user to run `bun ios/Scripts/translate-xcstrings.mjs` when other supported languages should be generated.
- The translator uses six shared request slots across languages, preserves catalog order, and atomically saves each completed batch. Reruns fill missing translations and target-language units marked `needs_review` or `new`; other existing translations are retained.
- When English or Norwegian wording changes through `xcstrings-set`, the helper automatically marks other existing translations `needs_review`, except languages supplied in the same command. Unchanged wording and metadata-only edits do not trigger this. For source edits made outside the helper, mark affected translations `needs_review` before running the translator.
- Request failures and invalid translations are reported immediately and return a nonzero exit status. Interrupting saves completed work and aborts pending requests; rerun to resume.
- Run `bun test ios/Scripts/translate-xcstrings.test.mjs` for translator regression checks without API calls.


## Validation and conventions

- Dot-separated keys generate camelCase symbols; inspect generated signatures instead of guessing argument types. Preserve the existing Int32 wrapping where the generated symbol requires it.
- For relevant changes, `./lint-strings` checks hardcoded UI strings and `ios/Scripts/validate-localization.sh` checks catalog integrity.
- Keep `ios/Resources/Localization/App/Localizable.xcstrings` as the app catalog source and preserve system locale / FormatStyle conventions.
