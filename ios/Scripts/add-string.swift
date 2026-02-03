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

private struct Config {
    let key: String
    let englishValue: String
    let norwegianValue: String
    let catalogPath: String
}

// MARK: - Errors

private enum AddStringError: Error, CustomStringConvertible {
    case missingArguments
    case fileNotFound(String)
    case keyAlreadyExists(String)
    case invalidJSON

    var description: String {
        switch self {
        case .missingArguments:
            return """
            Usage: swift run add-string --key <key> --en <english> --nb <norwegian>

            Example:
              swift run add-string --key "settings.profile.saveButton" --en "Save Changes" --nb "Lagre endringer"

            Options:
              --key    The localization key (e.g., "feature.context.description")
              --en     The English translation
              --nb     The Norwegian (Bokmål) translation
              --catalog Optional path to xcstrings file (defaults to App catalog)
            """
        case .fileNotFound(let path):
            return "String catalog not found: \(path)"
        case .keyAlreadyExists(let key):
            return "Key '\(key)' already exists in the catalog. Use Xcode to edit existing keys."
        case .invalidJSON:
            return "Failed to parse string catalog JSON"
        }
    }
}

// MARK: - Main

private func parseArgs() throws -> Config {
    var key: String?
    var english: String?
    var norwegian: String?
    var catalogPath: String?

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--key", "-k":
            key = iterator.next()
        case "--en", "--english":
            english = iterator.next()
        case "--nb", "--norwegian":
            norwegian = iterator.next()
        case "--catalog", "-c":
            catalogPath = iterator.next()
        case "--help", "-h":
            throw AddStringError.missingArguments
        default:
            continue
        }
    }

    guard let key, let english, let norwegian else {
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
        key: key,
        englishValue: english,
        norwegianValue: norwegian,
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

    // Check if key already exists
    if var existingEntry = catalog.strings[config.key] {
        // Key exists - check if we need to add missing translations
        var localizations = existingEntry.localizations ?? [:]
        var added: [String] = []

        if localizations["en"] == nil {
            localizations["en"] = CatalogLocalization(
                stringUnit: CatalogStringUnit(state: "translated", value: config.englishValue)
            )
            added.append("en")
        }

        if localizations["nb"] == nil {
            localizations["nb"] = CatalogLocalization(
                stringUnit: CatalogStringUnit(state: "translated", value: config.norwegianValue)
            )
            added.append("nb")
        }

        if added.isEmpty {
            throw AddStringError.keyAlreadyExists(config.key)
        }

        existingEntry.localizations = localizations
        catalog.strings[config.key] = existingEntry

        print("✓ Added missing translations (\(added.joined(separator: ", "))) to '\(config.key)'")
    } else {
        // Create new entry with en and nb translations
        let newEntry = CatalogEntry(
            extractionState: "manual",
            localizations: [
                "en": CatalogLocalization(
                    stringUnit: CatalogStringUnit(state: "translated", value: config.englishValue)
                ),
                "nb": CatalogLocalization(
                    stringUnit: CatalogStringUnit(state: "translated", value: config.norwegianValue)
                )
            ]
        )

        catalog.strings[config.key] = newEntry
        print("✓ Added '\(config.key)' to string catalog")
    }

    // Write back (pretty printed)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outputData = try encoder.encode(catalog)

    // JSONEncoder escapes forward slashes by default, but xcstrings files don't
    var outputString = String(data: outputData, encoding: .utf8)!
    outputString = outputString.replacingOccurrences(of: "\\/", with: "/")

    try outputString.write(toFile: config.catalogPath, atomically: true, encoding: .utf8)

    // Generate symbol name (convert key.like.this to keyLikeThis)
    let symbolName = generateSymbolName(from: config.key)

    print("")
    print("Usage in code:")
    print("  Text(.\(symbolName))")
    print("  String(localized: .\(symbolName))")
    print("")
    print("⚠ Remember to run translate-xcstrings.mjs to add other languages!")
}

private func generateSymbolName(from key: String) -> String {
    // Convert "feature.context.description" to "featureContextDescription"
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
