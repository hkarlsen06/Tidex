#!/usr/bin/env swift

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

private struct StringEntry {
    let key: String
    let englishValue: String
    let norwegianValue: String
}

private struct Config {
    let entries: [StringEntry]
    let catalogPath: String
}

// MARK: - Errors

private enum AddStringError: Error, CustomStringConvertible {
    case missingArguments
    case fileNotFound(String)
    case keyAlreadyExists(String)
    case invalidJSON
    case incompleteEntry(String)

    var description: String {
        switch self {
        case .missingArguments:
            return """
            Usage: add-strings --key <key> --en <english> --nb <norwegian> [--key <key2> --en <en2> --nb <nb2> ...]

            Examples:
              add-strings --key "settings.save" --en "Save" --nb "Lagre"
              add-strings --key "btn.ok" --en "OK" --nb "OK" --key "btn.cancel" --en "Cancel" --nb "Avbryt"

            Options:
              --key, -k    The localization key (repeatable for multiple strings)
              --en         The English translation (must follow its --key)
              --nb         The Norwegian (Bokmal) translation (must follow its --key)
              --catalog, -c  Optional path to xcstrings file (defaults to App catalog)
            """
        case .fileNotFound(let path):
            return "String catalog not found: \(path)"
        case .keyAlreadyExists(let key):
            return "Key '\(key)' already exists in the catalog. Use Xcode to edit existing keys."
        case .invalidJSON:
            return "Failed to parse string catalog JSON"
        case .incompleteEntry(let key):
            return "Incomplete entry for key '\(key)': both --en and --nb values are required after each --key"
        }
    }
}

// MARK: - Main

private func parseArgs() throws -> Config {
    var entries: [StringEntry] = []
    var catalogPath: String?

    // Collect raw tokens grouped by --key
    var currentKey: String?
    var currentEn: String?
    var currentNb: String?

    func flushEntry() throws {
        guard let key = currentKey else { return }
        guard let en = currentEn, let nb = currentNb else {
            throw AddStringError.incompleteEntry(key)
        }
        entries.append(StringEntry(key: key, englishValue: en, norwegianValue: nb))
        currentKey = nil
        currentEn = nil
        currentNb = nil
    }

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--key", "-k":
            // Flush previous entry if any
            try flushEntry()
            currentKey = iterator.next()
        case "--en", "--english":
            currentEn = iterator.next()
        case "--nb", "--norwegian":
            currentNb = iterator.next()
        case "--catalog", "-c":
            catalogPath = iterator.next()
        case "--help", "-h":
            throw AddStringError.missingArguments
        default:
            continue
        }
    }

    // Flush final entry
    try flushEntry()

    guard !entries.isEmpty else {
        throw AddStringError.missingArguments
    }

    // Default catalog path
    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()
    let defaultCatalog = scriptsDir
        .appendingPathComponent("../Resources/Localization/App/Localizable.xcstrings")
        .standardizedFileURL
        .path

    return Config(
        entries: entries,
        catalogPath: catalogPath ?? defaultCatalog
    )
}

private func run() throws {
    let config = try parseArgs()

    guard FileManager.default.fileExists(atPath: config.catalogPath) else {
        throw AddStringError.fileNotFound(config.catalogPath)
    }

    // Read catalog
    let catalogURL = URL(fileURLWithPath: config.catalogPath)
    let catalogData = try Data(contentsOf: catalogURL)
    var catalog = try JSONDecoder().decode(Catalog.self, from: catalogData)

    var addedCount = 0
    var updatedCount = 0

    for entry in config.entries {
        if var existingEntry = catalog.strings[entry.key] {
            // Key exists - check if we need to add missing translations
            var localizations = existingEntry.localizations ?? [:]
            var added: [String] = []

            if localizations["en"] == nil {
                localizations["en"] = CatalogLocalization(
                    stringUnit: CatalogStringUnit(state: "translated", value: entry.englishValue)
                )
                added.append("en")
            }

            if localizations["nb"] == nil {
                localizations["nb"] = CatalogLocalization(
                    stringUnit: CatalogStringUnit(state: "translated", value: entry.norwegianValue)
                )
                added.append("nb")
            }

            if added.isEmpty {
                print("  Skipped '\(entry.key)' (already has en + nb translations)")
                continue
            }

            existingEntry.localizations = localizations
            catalog.strings[entry.key] = existingEntry
            updatedCount += 1
            print("  Updated '\(entry.key)' — added missing: \(added.joined(separator: ", "))")
        } else {
            // Create new entry
            let newEntry = CatalogEntry(
                extractionState: "manual",
                localizations: [
                    "en": CatalogLocalization(
                        stringUnit: CatalogStringUnit(state: "translated", value: entry.englishValue)
                    ),
                    "nb": CatalogLocalization(
                        stringUnit: CatalogStringUnit(state: "translated", value: entry.norwegianValue)
                    )
                ]
            )

            catalog.strings[entry.key] = newEntry
            addedCount += 1
            print("  Added '\(entry.key)'")
        }
    }

    // Write back (pretty printed)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outputData = try encoder.encode(catalog)

    // JSONEncoder escapes forward slashes by default, but xcstrings files don't
    var outputString = String(data: outputData, encoding: .utf8)!
    outputString = outputString.replacingOccurrences(of: "\\/", with: "/")

    try outputString.write(toFile: config.catalogPath, atomically: true, encoding: .utf8)

    // Summary
    print("")
    if addedCount > 0 || updatedCount > 0 {
        var parts: [String] = []
        if addedCount > 0 { parts.append("\(addedCount) added") }
        if updatedCount > 0 { parts.append("\(updatedCount) updated") }
        print("Done: \(parts.joined(separator: ", "))")
    }

    // Show usage hints for new entries
    if addedCount > 0 {
        print("")
        print("Usage in code:")
        for entry in config.entries {
            let symbolName = generateSymbolName(from: entry.key)
            print("  Text(.\(symbolName))")
        }
        print("")
        print("Remember to run translate-xcstrings.mjs to add other languages!")
    }
}

private func generateSymbolName(from key: String) -> String {
    let parts = key.split(separator: ".")
    guard let first = parts.first else { return key }
    let rest = parts.dropFirst().map { part in
        part.prefix(1).uppercased() + part.dropFirst()
    }
    return String(first) + rest.joined()
}

do {
    try run()
} catch {
    print("Error: \(error)")
    exit(1)
}
