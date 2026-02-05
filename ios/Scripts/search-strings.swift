#!/usr/bin/env swift

import Foundation

// MARK: - Models (must match add-strings.swift exactly to avoid mangling JSON)

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

private struct MatchResult {
    let key: String
    let entry: CatalogEntry
    let matchedIn: MatchLocation
}

private enum MatchLocation {
    case key
    case value(language: String)
    case both
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
            if let next = iterator.next(), let n = Int(next) {
                limit = n
            }
        case "--catalog", "-c":
            catalogPath = iterator.next()
        case "--help", "-h":
            throw SearchError.missingArguments
        default:
            if !arg.hasPrefix("-") && query == nil {
                query = arg
            }
        }
    }

    guard let query else {
        throw SearchError.missingArguments
    }

    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()
    let defaultCatalog = scriptsDir
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

private func run() throws {
    let config = try parseArgs()

    guard FileManager.default.fileExists(atPath: config.catalogPath) else {
        throw SearchError.fileNotFound(config.catalogPath)
    }

    let catalogURL = URL(fileURLWithPath: config.catalogPath)
    let catalogData = try Data(contentsOf: catalogURL)
    let catalog = try JSONDecoder().decode(Catalog.self, from: catalogData)

    let queryLower = config.query.lowercased()
    var matches: [(key: String, entry: CatalogEntry, matchedIn: String)] = []

    for (key, entry) in catalog.strings {
        var matchReasons: [String] = []

        // Search in key
        if config.searchKeys && key.lowercased().contains(queryLower) {
            matchReasons.append("key")
        }

        // Search in values
        if config.searchValues, let localizations = entry.localizations {
            for (locale, localization) in localizations {
                if let value = localization.stringUnit?.value,
                   value.lowercased().contains(queryLower) {
                    matchReasons.append(locale)
                }
                // Also search in plural/device variations
                if let variations = localization.variations {
                    if let plural = variations.plural {
                        for (_, form) in plural {
                            if let value = form.stringUnit?.value,
                               value.lowercased().contains(queryLower) {
                                matchReasons.append("\(locale)/plural")
                                break
                            }
                        }
                    }
                    if let device = variations.device {
                        for (_, form) in device {
                            if let value = form.stringUnit?.value,
                               value.lowercased().contains(queryLower) {
                                matchReasons.append("\(locale)/device")
                                break
                            }
                        }
                    }
                }
            }
        }

        if !matchReasons.isEmpty {
            // Deduplicate reasons
            let uniqueReasons = Array(Set(matchReasons)).sorted()
            matches.append((key: key, entry: entry, matchedIn: uniqueReasons.joined(separator: ", ")))
        }
    }

    // Sort by key
    matches.sort { $0.key < $1.key }

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
        printEntry(key: match.key, entry: match.entry, matchedIn: match.matchedIn, showSymbol: config.showSymbol)
    }
}

private func printEntry(key: String, entry: CatalogEntry, matchedIn: String, showSymbol: Bool) {
    // Key and match info
    print("  \(key)")

    // Extraction state
    let state = entry.extractionState ?? "automatic"
    print("    state: \(state)  |  matched in: \(matchedIn)")

    // Translations
    if let localizations = entry.localizations {
        for locale in localizations.keys.sorted() {
            let localization = localizations[locale]!
            if let value = localization.stringUnit?.value {
                let translationState = localization.stringUnit?.state ?? "unknown"
                let stateIndicator: String
                switch translationState {
                case "translated": stateIndicator = "ok"
                case "needs_review": stateIndicator = "review"
                case "new": stateIndicator = "new"
                default: stateIndicator = translationState
                }
                print("    \(locale): \"\(value)\" [\(stateIndicator)]")
            } else if let variations = localization.variations {
                if let plural = variations.plural {
                    let forms = plural.keys.sorted().map { form -> String in
                        let value = plural[form]?.stringUnit?.value ?? "?"
                        return "\(form)=\"\(value)\""
                    }
                    print("    \(locale): (plural) \(forms.joined(separator: ", "))")
                }
                if let device = variations.device {
                    let forms = device.keys.sorted().map { form -> String in
                        let value = device[form]?.stringUnit?.value ?? "?"
                        return "\(form)=\"\(value)\""
                    }
                    print("    \(locale): (device) \(forms.joined(separator: ", "))")
                }
            }
        }
    } else {
        print("    (no translations)")
    }

    // Swift symbol
    if showSymbol {
        let symbol = generateSymbolName(from: key)
        print("    symbol: .\(symbol)")
    }
}

do {
    try run()
} catch {
    print("Error: \(error)")
    exit(1)
}
