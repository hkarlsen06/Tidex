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
- Add every key to the App catalog, widget, share extension and Siri strings too. Code in `ios/Shared/` compiles into several targets, and per-target catalogs drifted apart and broke builds, so they were merged into this one. Keep it the only catalog.
- `xcstrings-set` rejects underscores in new keys. Use dot-separated camelCase segments.
- The helper writes the catalog exactly as Xcode's String Catalog editor saves it, so a later save in Xcode leaves no diff. The translator, `reset-translations.mjs` and `audit-strings --remove` write through it too (`scripts/xcstrings-set --format-stdin`). Edit catalogs with these scripts or Xcode, not by hand or with other JSON tools.
- Use `--locale <code>=<value>` for additional languages if a specific non-generated locale edit is needed.
- Use Xcode's String Catalog editor or XLIFF export/import for pluralization, substitutions, device variants, or bulk translator workflows.
- The pre-commit hook (`.husky/pre-commit`) runs `bun run localize` on every staged catalog, which calls the machine translator and stages the result. A commit with English and Norwegian copy therefore fills the other languages. A commit made with `--no-verify` skips that, so run `bun run localize -- ios/Resources/Localization/App/Localizable.xcstrings` before the work lands.
- The translator calls Claude Opus 5.5 through the `ant` CLI, so it needs `ant` on `PATH` and a login from `ant auth login` (or `ANTHROPIC_API_KEY`). `TIDEX_TRANSLATE_MODEL` and `TIDEX_TRANSLATE_EFFORT` override the model and the effort, which defaults to `high`.
- Every request carries `ios/Scripts/translation-guide.md`, the strings with their translator comments, and for each string the Swift lines around its uses and up to six existing translations of related strings in the target language: strings on the same screen and strings that share its rarer words. A request never carries the whole catalog, because each of the 46 languages gets its own requests and the catalog made a commit with three new strings cost about $18. Put product vocabulary and tone rules in the guide. A string's comment is still its most direct context, so say what each placeholder holds and where the string appears.
- The translator sends up to 48 requests at once, one per language for a small change, keeps Xcode's catalog format, and atomically saves completed batches. Reruns fill missing translations and target-language units marked `needs_review` or `new`; other existing translations are retained. A unit marked `needs_review` is sent with its current text, and the translator keeps the wording that still fits.
- Plural strings get every plural category the target language uses for whole numbers, for example `one`, `few`, `many` and `other` in Russian. A plain string with one count, such as `%lld selected`, gets plural forms in the languages that inflect the words around the number, and stays plain elsewhere.
- A translation may reorder arguments with numbered specifiers (`%2$@ ... %1$lld`). The translator rejects a translation whose specifier would read an argument of another type.
- When English or Norwegian wording changes through `xcstrings-set`, the helper automatically marks other existing translations `needs_review`, except languages supplied in the same command. Unchanged wording and metadata-only edits do not trigger this. For source edits made outside the helper, mark affected translations `needs_review` before running the translator.
- Request failures and invalid translations are reported immediately and return a nonzero exit status. Interrupting saves completed work and aborts pending requests; rerun to resume.
- Run `bun test ios/Scripts/translate-xcstrings.test.mjs` for translator regression checks without API calls.


## Validation and conventions

- Dot-separated keys generate camelCase symbols, and underscores also start a new word: `settings.pay.add_job.title` becomes `.settingsPayAddJobTitle`. Older keys mix `snake_case` and `camelCase` segments, so search the catalog with `bun run ios:l10n:search` instead of guessing the key.
- Argument types of generated symbols vary (`Int` or `Int32`). After a build, read them in `~/Library/Developer/Xcode/DerivedData/Tidex-*/Build/Intermediates.noindex/Tidex.build/Debug-iphonesimulator/TidexApp.build/DerivedSources/GeneratedStringSymbols_Localizable.swift`, or copy an existing call site of the same symbol.
- Permission purpose strings are not in the catalog. They are in `ios/TidexApp/Supporting/Info.plist` and in `ios/TidexApp/Resources/<locale>.lproj/InfoPlist.strings`. Keep `NSLocationWhenInUseUsageDescription` even though Tidex never asks for location. The Exyte Chat fork calls `CLLocationManager`, and App Store Connect flagged uploads without the string (ITMS-90683). The fork also calls the microphone permission API, but add `NSMicrophoneUsageDescription` only if Apple flags it.
- For relevant changes, `ios/lint-strings` checks hardcoded UI strings and `ios/Scripts/validate-localization.sh` checks catalog integrity.
- Keep `ios/Resources/Localization/App/Localizable.xcstrings` as the app catalog source and preserve system locale / FormatStyle conventions.
- `bun run ios:l10n:validate` fails if a dot key lacks English, Norwegian or a translator comment, if any language is missing or not marked translated, if a translation's format specifiers differ from English, or if an entry is stale.
- Xcode also extracts keys that aren't dot notation from literals such as `Text("·")`, `Text("\(a) / \(b)")`, `Text("Tidex")` and the English-only admin and debug screens. These stay English. Mark them `shouldTranslate: false` with no translations (in Xcode, "Mark for Translation" off), and the translator skips them. Any key with words that users see gets a dot key instead.
- Widget strings are `widget.*` keys. App Intents metadata (`title`, `description`, `@Parameter(title:)`) needs compile-time literals, so it names the catalog key as a string, for example `"widget.name.friendsShift"`.
