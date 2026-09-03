#!/usr/bin/env swift  // swiftlint:disable:next blanket_disable_command  // swiftlint:disable:next blanket_disable_command  // swiftlint:disable conditional_returns_on_newline cyclomatic_complexity
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable discouraged_optional_collection explicit_type_interface file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable function_body_length multiline_arguments_brackets no_direct_print
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_enum_cases switch_case_on_newline

import Foundation

// MARK: - Models

private struct Catalog: Codable {
  var sourceLanguage: String
  var strings: [String: CatalogEntry]
  var version: String
}

private struct CatalogEntry: Codable {
  var extractionState: String?
  var localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Codable {
  var stringUnit: CatalogStringUnit?
  var variations: CatalogVariations?
}

private struct CatalogVariations: Codable {
  var plural: [String: CatalogPluralForm]?
  var device: [String: CatalogPluralForm]?
}

private struct CatalogPluralForm: Codable {
  var stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Codable {
  var state: String
  var value: String
}

// MARK: - Config

private struct Config {
  let query: String
  let searchKeys: Bool
  let searchValues: Bool
  let catalogPath: String
  let showSymbol: Bool
  let limit: Int?
}

// MARK: - Errors

private enum SearchError: Error, CustomStringConvertible {
  case missingArguments
  case fileNotFound(String)
  case noResults(String)

  var description: String {
    switch self {
    case .missingArguments:
      return """
        Usage: search-strings <query> [options]

        Searches the string catalog for keys and/or values matching the query.

        Examples:
          search-strings "save"                  Search keys and values
          search-strings "save" --keys-only      Search keys only
          search-strings "save" --values-only    Search values only
          search-strings "lagre" --limit 5       Limit results

        Options:
          <query>        The search term (case-insensitive substring match)
          --keys-only    Only search in localization keys
          --values-only  Only search in translation values
          --no-symbol    Don't show the Swift symbol name
          --limit N      Limit the number of results shown
          --catalog, -c  Path to xcstrings file (defaults to App catalog)
          --help, -h     Show this help message
        """

    case .fileNotFound(let path):
      return "String catalog not found: \(path)"

    case .noResults(let query):
      return "No strings found matching '\(query)'"
    }
  }
}

// MARK: - Match Result

private struct SearchMatch {
  let key: String
  let entry: CatalogEntry
  let matchedIn: String
}

// MARK: - Main

private func parseArgs() throws -> Config {
  var query: String?
  var keysOnly = false
  var valuesOnly = false
  var catalogPath: String?
  var showSymbol = true
  var limit: Int?

  var iterator = CommandLine.arguments.dropFirst().makeIterator()
  while let arg = iterator.next() {
    switch arg {
    case "--keys-only", "-k":
      keysOnly = true

    case "--values-only", "-v":
      valuesOnly = true

    case "--no-symbol":
      showSymbol = false

    case "--limit", "-l":
      limit = iterator.next().flatMap(Int.init)

    case "--catalog", "-c":
      catalogPath = iterator.next()

    case "--help", "-h":
      throw SearchError.missingArguments

    default:
      if !arg.hasPrefix("-"), query == nil {
        query = arg
      }
    }
  }

  guard let query else {
    throw SearchError.missingArguments
  }

  let scriptURL = URL(fileURLWithPath: #filePath)
  let scriptsDir = scriptURL.deletingLastPathComponent()
  let defaultCatalog =
    scriptsDir
    .appendingPathComponent("../Resources/Localization/App/Localizable.xcstrings")
    .standardizedFileURL
    .path

  return Config(
    query: query,
    searchKeys: !valuesOnly,
    searchValues: !keysOnly,
    catalogPath: catalogPath ?? defaultCatalog,
    showSymbol: showSymbol,
    limit: limit
  )
}

private func generateSymbolName(from key: String) -> String {
  let parts = key.split(separator: ".")
  guard let first = parts.first else { return key }
  let rest = parts.dropFirst().map { part in
    part.prefix(1).uppercased() + part.dropFirst()
  }
  return String(first) + rest.joined()
}

private func searchVariations(_ variations: CatalogVariations, query: String, locale: String)
  -> [String]
{
  var reasons: [String] = []
  if let plural = variations.plural {
    for (_, form) in plural where form.stringUnit?.value.lowercased().contains(query) == true {
      reasons.append("\(locale)/plural")
      break
    }
  }
  if let device = variations.device {
    for (_, form) in device where form.stringUnit?.value.lowercased().contains(query) == true {
      reasons.append("\(locale)/device")
      break
    }
  }
  return reasons
}

private func findMatches(in catalog: Catalog, config: Config) -> [SearchMatch] {
  let queryLower = config.query.lowercased()
  var matches: [SearchMatch] = []

  for (key, entry) in catalog.strings {
    var matchReasons: [String] = []

    if config.searchKeys, key.lowercased().contains(queryLower) {
      matchReasons.append("key")
    }

    if config.searchValues, let localizations = entry.localizations {
      for (locale, localization) in localizations {
        if let value = localization.stringUnit?.value,
          value.lowercased().contains(queryLower)
        {
          matchReasons.append(locale)
        }
        if let variations = localization.variations {
          matchReasons.append(
            contentsOf: searchVariations(variations, query: queryLower, locale: locale))
        }
      }
    }

    if !matchReasons.isEmpty {
      let uniqueReasons = Array(Set(matchReasons)).sorted()
      matches.append(
        SearchMatch(key: key, entry: entry, matchedIn: uniqueReasons.joined(separator: ", ")))
    }
  }

  return matches.sorted { $0.key < $1.key }
}

private func run() throws {
  let config = try parseArgs()

  guard FileManager.default.fileExists(atPath: config.catalogPath) else {
    throw SearchError.fileNotFound(config.catalogPath)
  }

  let catalogURL = URL(fileURLWithPath: config.catalogPath)
  let catalogData = try Data(contentsOf: catalogURL)
  let catalog = try JSONDecoder().decode(Catalog.self, from: catalogData)

  var matches = findMatches(in: catalog, config: config)

  guard !matches.isEmpty else {
    throw SearchError.noResults(config.query)
  }

  let total = matches.count
  if let limit = config.limit {
    matches = Array(matches.prefix(limit))
  }

  print("Found \(total) string(s) matching '\(config.query)'")
  if let limit = config.limit, total > limit {
    print("(showing first \(limit))")
  }
  print("")

  for (index, match) in matches.enumerated() {
    if index > 0 { print("") }
    printEntry(
      key: match.key, entry: match.entry, matchedIn: match.matchedIn, showSymbol: config.showSymbol)
  }
}

private func stateIndicator(for state: String) -> String {
  switch state {
  case "translated": return "ok"
  case "needs_review": return "review"
  case "new": return "new"
  default: return state
  }
}

private func formatVariations(_ forms: [String: CatalogPluralForm], kind: String) -> String {
  let formatted = forms.keys.sorted().map { form -> String in
    let value = forms[form]?.stringUnit?.value ?? "?"
    return "\(form)=\"\(value)\""
  }
  return "(\(kind)) \(formatted.joined(separator: ", "))"
}

private func printEntry(key: String, entry: CatalogEntry, matchedIn: String, showSymbol: Bool) {
  print("  \(key)")

  let state = entry.extractionState ?? "automatic"
  print("    state: \(state)  |  matched in: \(matchedIn)")

  if let localizations = entry.localizations {
    for locale in localizations.keys.sorted() {
      guard let localization = localizations[locale] else {
        continue
      }
      if let value = localization.stringUnit?.value {
        let indicator = stateIndicator(for: localization.stringUnit?.state ?? "unknown")
        print("    \(locale): \"\(value)\" [\(indicator)]")
      } else if let variations = localization.variations {
        if let plural = variations.plural {
          print("    \(locale): \(formatVariations(plural, kind: "plural"))")
        }
        if let device = variations.device {
          print("    \(locale): \(formatVariations(device, kind: "device"))")
        }
      }
    }
  } else {
    print("    (no translations)")
  }

  if showSymbol {
    print("    symbol: .\(generateSymbolName(from: key))")
  }
}

do {
  try run()
} catch {
  print("Error: \(error)")
  exit(1)
}
