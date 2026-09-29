// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable discouraged_optional_collection explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_direct_print prefixed_toplevel_constant
import Foundation

// Checks that the string catalog is ready to ship:
// - Every dot-notation key has English, Norwegian and a translator comment.
// - Every dot-notation key has a translated value in every language the catalog uses.
// - Every translation uses the same format specifiers as English.
// - Every other key (symbols, format-only compositions, English-only admin text) is marked
//   shouldTranslate = false, so the translator skips it.
// - No entry is stale.

private typealias JSON = [String: Any]

private let requiredLocales = ["en", "nb"]

private func isDotNotationKey(_ key: String) -> Bool {
  key.range(of: #"^[a-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$"#, options: .regularExpression) != nil
}

private struct StringUnit {
  let path: String
  let state: String?
  let value: String
}

/// Flattens a localization into its string units, following plural, device and substitution
/// variations. The path names the variation case, e.g. "plural.one/".
private func units(in node: JSON, path: String = "") -> [StringUnit] {
  var result: [StringUnit] = []
  if let unit = node["stringUnit"] as? JSON, let value = unit["value"] as? String {
    result.append(StringUnit(path: path, state: unit["state"] as? String, value: value))
  }
  for (kind, cases) in (node["variations"] as? JSON) ?? [:] {
    for (name, child) in (cases as? JSON) ?? [:] {
      if let child = child as? JSON { result += units(in: child, path: path + "\(kind).\(name)/") }
    }
  }
  for (name, substitution) in (node["substitutions"] as? JSON) ?? [:] {
    if let substitution = substitution as? JSON {
      result += units(in: substitution, path: path + "sub.\(name)/")
    }
  }
  return result
}

private let specifierRegex = try? NSRegularExpression(
  pattern: #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcCsSpaAi]|%#@\w+@"#)

/// Format specifiers without positional indexes, sorted, so reordered arguments still match.
private func specifiers(_ value: String) -> [String] {
  let range = NSRange(value.startIndex..., in: value)
  return (specifierRegex?.matches(in: value, range: range) ?? []).compactMap { match in
    Range(match.range, in: value).map {
      String(value[$0]).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression)
    }
  }.sorted()
}

/// Plural cases other than "other" may spell out the count ("1 month"), so they only need a
/// subset of the English specifiers.
private func specifiersMatch(_ value: String, english: String, path: String) -> Bool {
  let actual = specifiers(value)
  let expected = specifiers(english)
  guard path.contains("plural."), !path.contains("plural.other") else { return actual == expected }
  var remaining = expected
  for specifier in actual {
    guard let index = remaining.firstIndex(of: specifier) else { return false }
    remaining.remove(at: index)
  }
  return true
}

private struct Report {
  var problems: [String: [String]] = [:]

  mutating func add(_ problem: String, _ detail: String) {
    problems[problem, default: []].append(detail)
  }
}

private let translateHint = "(run bun ios/Scripts/translate-xcstrings.mjs)"

private func validate(_ strings: JSON) -> Report {
  var report = Report()
  let locales = Set(
    strings.flatMap { key, entry -> [String] in
      guard isDotNotationKey(key), let entry = entry as? JSON else { return [] }
      return Array(((entry["localizations"] as? JSON) ?? [:]).keys)
    }
  ).sorted()

  for (key, entry) in strings {
    guard let entry = entry as? JSON else { continue }
    if entry["extractionState"] as? String == "stale" {
      report.add("Stale entries (no longer in code, delete them)", key)
    } else if !isDotNotationKey(key) {
      if entry["shouldTranslate"] as? Bool != false {
        report.add(
          "Keys that are not dot notation (use a dot key, or mark shouldTranslate = false)", key)
      }
    } else if entry["shouldTranslate"] as? Bool != false {
      validateEntry(key: key, entry: entry, locales: locales, report: &report)
    }
  }
  return report
}

private func validateEntry(key: String, entry: JSON, locales: [String], report: inout Report) {
  if ((entry["comment"] as? String) ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
    report.add("Missing translator comment", key)
  }
  let localizations = (entry["localizations"] as? JSON) ?? [:]
  for locale in requiredLocales where localizations[locale] == nil {
    report.add("Missing \(locale)", key)
  }
  let englishUnits = Dictionary(
    units(in: (localizations["en"] as? JSON) ?? [:]).map { ($0.path, $0.value) },
    uniquingKeysWith: { first, _ in first })

  for locale in locales {
    guard let localization = localizations[locale] as? JSON else {
      report.add("Missing translations \(translateHint)", "\(key) [\(locale)]")
      continue
    }
    for unit in units(in: localization) {
      validateUnit(unit, key: key, locale: locale, englishUnits: englishUnits, report: &report)
    }
  }
}

private func validateUnit(
  _ unit: StringUnit, key: String, locale: String, englishUnits: [String: String],
  report: inout Report
) {
  if unit.state != "translated" {
    report.add(
      "Translations not marked translated \(translateHint)",
      "\(key) [\(locale)] \(unit.state ?? "no state")")
  }
  // A language can use plural cases English doesn't have (e.g. "few"), so compare with "other".
  let englishOther = englishUnits.first { $0.key.hasSuffix("plural.other/") }?.value
  let fallback = unit.path.contains("plural.") ? englishOther : nil
  guard let english = englishUnits[unit.path] ?? fallback else { return }
  if !specifiersMatch(unit.value, english: english, path: unit.path) {
    report.add(
      "Format specifiers differ from English",
      "\(key) [\(locale)] \(unit.path)\"\(unit.value)\"")
  }
}

private func run() throws {
  let scriptsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  var catalogURL = scriptsDir.appendingPathComponent(
    "../Resources/Localization/App/Localizable.xcstrings"
  ).standardizedFileURL
  var arguments = CommandLine.arguments.dropFirst().makeIterator()
  while let argument = arguments.next() {
    if argument == "--catalog", let value = arguments.next() {
      catalogURL = URL(fileURLWithPath: value)
    }
  }

  let data = try Data(contentsOf: catalogURL)
  guard let catalog = try JSONSerialization.jsonObject(with: data) as? JSON,
    let strings = catalog["strings"] as? JSON
  else {
    print("Could not read strings from \(catalogURL.path)")
    exit(1)
  }

  let report = validate(strings)
  guard !report.problems.isEmpty else {
    print("Localization validation passed. Catalog entries: \(strings.count).")
    return
  }
  for (problem, details) in report.problems.sorted(by: { $0.key < $1.key }) {
    print("\(problem): \(details.count)")
    for detail in details.sorted().prefix(25) { print("  \(detail)") }
    if details.count > 25 { print("  ... and \(details.count - 25) more") }
  }
  exit(1)
}

try run()
