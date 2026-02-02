# iOS Localization and Adding New Languages

This document covers how Tidex iOS localization works and how to add a new language safely.

## Source of truth

- String catalog: `ios/App/TidexApp/Localizable.xcstrings`
- Symbols are generated automatically by Xcode when `STRING_CATALOG_GENERATE_SYMBOLS = YES`.
- Runtime access: Xcode-generated `LocalizedStringResource` symbols and `String(localized:)`.

## Current approach

Use Xcode-generated `LocalizedStringResource` symbols:

```swift
// Simple strings
Text(.statsMonthlyGoalRemaining)
String(localized: .statsMonthlyGoalRemaining)

// Formatted strings (symbols become functions)
// String catalog key "common.inDays" with %lld generates:
Text(String(localized: .commonInDays(Int32(days))))
```

Format string symbols are generated as functions. The `%lld` specifier generates `Int32` parameters,
so wrap `Int` values with `Int32()`.

Avoid raw string keys, manual `.replacingOccurrences`, and `String(format:)` where `FormatStyle` is appropriate.

## Adding a new language

### 1) Add the language to the String Catalog

Open `Localizable.xcstrings` in Xcode, add the new language (Editor -> Add Localization),
and fill in translations for the new language. Keep `state: translated` for each string unit.

### 2) Update any per-locale special casing

Search for hard-coded checks like `tidexIsNorwegian` or hard-coded locales like `"nb_NO"` and update
them for the new language. These are not automatically covered by adding to the catalog.

Useful ripgrep queries:

```bash
rg -n "tidexIsNorwegian|nb_NO|en_US|localeIdentifier" ios/App/TidexApp/Native
```

Common areas that currently contain Norwegian/English-only logic:

- Date/number formatting in export and PDF generation
- Terms/Privacy URLs based on `currentLocale.rawValue`
- Notification reminder copy and calendar formatting
- Certain onboarding and sharing strings that are still hard-coded

### 3) Update external URLs if needed

Some URLs include `Locale.current.tidexLanguageCode` (Terms/Privacy).
Ensure the backend/site supports the new language path or add a fallback.

### 4) Validate

Run the localization validator (requires Swift toolchain):

```bash
swift run --package-path ios/App/Scripts validate-localization
```

## Notes

- The app uses system locale by default (no explicit locale override in `RootView`).
- Widgets and notifications use the app group locale value; ensure the new locale raw value
  matches the language code you want persisted.
- Prefer `FormatStyle` for numbers/dates. If you must format a year without grouping,
  pass a string (ex: `String(focusYear)`) to the localization call.
