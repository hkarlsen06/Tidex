# iOS Localization and Adding New Languages

This document covers how Tidex iOS localization works and how to add a new language safely.

## Source of truth

- `ios/Resources/Localization/App/Localizable.xcstrings` is the only catalog. The app, the widget, the share extension and Siri Intents all include it.
- Symbols are generated automatically by Xcode when `STRING_CATALOG_GENERATE_SYMBOLS = YES`.
- Runtime access: Xcode-generated `LocalizedStringResource` symbols and `String(localized:)`.

## Current approach

Use Xcode-generated `LocalizedStringResource` symbols:

```swift
// Simple strings - SwiftUI Text
Text(.statsMonthlyGoalRemaining)

// Simple strings - non-SwiftUI
String(localized: .statsMonthlyGoalRemaining)

// Formatted strings with single parameter (symbols become functions)
// String catalog key "common.inDays" with %lld generates:
Text(String(localized: .commonInDays(Int32(days))))
```

Format string symbols are generated as functions. The `%lld` specifier generates `Int32` parameters,
so wrap `Int` values with `Int32()`.

Avoid raw string keys, manual `.replacingOccurrences`, and `String(format:)` where `FormatStyle` is appropriate.

## Multi-parameter strings

**Important**: Xcode String Catalogs may not reliably generate function symbols for strings with
multiple format specifiers (e.g., `%1$lld h %2$lld min`). When this happens, compose the string
from individual localized parts:

```swift
// Instead of this (may not generate symbol):
String(localized: .notificationReminderHoursMinutes(hours, mins))

// Use composition with single-value symbols:
"\(hours) \(String(localized: .commonHoursShort)) \(mins) min \(String(localized: .commonBefore))"
```

This approach:
- Uses existing single-value localized symbols
- Avoids hardcoded locale checks
- Works reliably across all targets

## Date/Number formatting

For `DateFormatter` and `NumberFormatter` locale, use a helper function instead of checking locale strings:

```swift
// Good: Use a formatterLocale helper
private func formatterLocale(for locale: String) -> Locale {
    switch locale {
    case "no": return Locale(identifier: "nb_NO")
    case "de": return Locale(identifier: "de_DE")
    default: return Locale(identifier: "en_US")
    }
}

let formatter = DateFormatter()
formatter.locale = formatterLocale(for: locale)
formatter.setLocalizedDateFormatFromTemplate("EEE d")

// Bad: Hardcoded locale ternary
formatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
```

This pattern is acceptable because it's for formatting behavior, not text localization.
The system handles the actual text output based on the locale.

## What NOT to do

Never use hardcoded locale ternaries for text:

```swift
// BAD - hardcoded locale check for text
let title = locale == "no" ? "Vakter" : "Shifts"
let greeting = isNorwegian ? "Hei" : "Hello"

// GOOD - use String Catalog symbols
let title = String(localized: .widgetShifts)
let greeting = String(localized: .commonGreeting)
```

## Extension localization

The extensions use the same catalog as the app, so every key is available in every target.
Widget strings use the `widget.` prefix, for example `.widgetToday` and `.widgetShifts`.

## Adding a new language

### 1) Add the language to the String Catalog

Open `ios/Resources/Localization/App/Localizable.xcstrings` in Xcode, add the new language
(Editor -> Add Localization), and fill in translations. Keep `state: translated` for each string unit.

### 2) Update formatter locale helpers

Search for `formatterLocale` functions and add the new language case:

```swift
private func formatterLocale(for locale: String) -> Locale {
    switch locale {
    case "no": return Locale(identifier: "nb_NO")
    case "de": return Locale(identifier: "de_DE")  // Add new languages here
    default: return Locale(identifier: "en_US")
    }
}
```

### 3) Update any remaining special casing

Search for any remaining hard-coded locale checks:

```bash
rg -n "locale == |isNorwegian|nb_NO|en_US|localeIdentifier" ios/
```

Common areas that may need attention:
- Date/number formatting helpers
- Terms/Privacy URLs based on locale
- Data selection (e.g., `NorwegianHolidays` with `holiday.nameEN` vs `holiday.nameNO`)
- Motivational salutes array selection

### 4) Update external URLs if needed

Some URLs include `Locale.current.tidexLanguageCode` (Terms/Privacy).
Ensure the backend/site supports the new language path or add a fallback.

### 5) Validate

Run the localization validator (requires Swift toolchain):

```bash
swift run --package-path ios/Scripts validate-localization
```

## Notes

- The app uses system locale by default (no explicit locale override in `RootView`).
- Widgets use the app group locale value; ensure the new locale raw value
  matches the language code you want persisted.
- Prefer `FormatStyle` for numbers/dates. If you must format a year without grouping,
  pass a string (ex: `String(focusYear)`) to the localization call.
- Clean build (Cmd+Shift+K twice) may be needed after String Catalog changes for
  Xcode to regenerate symbols.
