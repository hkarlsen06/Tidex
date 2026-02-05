#!/usr/bin/env swift

import Foundation

// MARK: - Models (must match add-string.swift exactly to avoid mangling JSON)

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
    let catalogPath: String
    let dryRun: Bool
}

// MARK: - Errors

private enum DeleteStringError: Error, CustomStringConvertible {
    case missingArguments
    case fileNotFound(String)
    case keyNotFound(String)
    case invalidJSON

    var description: String {
        switch self {
        case .missingArguments:
            return """
            Usage: swift run delete-string --key <key>

            Example:
              swift run delete-string --key "settings.profile.saveButton"

            Options:
              --key      The localization key to delete (required)
              --catalog  Optional path to xcstrings file (defaults to App catalog)
              --dry-run  Show what would be deleted without modifying the file
            """
        case .fileNotFound(let path):
            return "String catalog not found: \(path)"
        case .keyNotFound(let key):
            return "Key '\(key)' not found in the catalog"
        case .invalidJSON:
            return "Failed to parse string catalog JSON"
        }
    }
}

// MARK: - Main

private func parseArgs() throws -> Config {
    var key: String?
    var catalogPath: String?
    var dryRun = false

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--key", "-k":
            key = iterator.next()
        case "--catalog", "-c":
            catalogPath = iterator.next()
        case "--dry-run", "-n":
            dryRun = true
        case "--help", "-h":
            throw DeleteStringError.missingArguments
        default:
            continue
        }
    }

    guard let key else {
        throw DeleteStringError.missingArguments
    }

    // Default catalog path (same as add-string)
    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()
    let defaultCatalog = scriptsDir
        .appendingPathComponent("../Resources/Localization/App/Localizable.xcstrings")
        .standardizedFileURL
        .path

    return Config(
        key: key,
        catalogPath: catalogPath ?? defaultCatalog,
        dryRun: dryRun
    )
}

private func run() throws {
    let config = try parseArgs()

    guard FileManager.default.fileExists(atPath: config.catalogPath) else {
        throw DeleteStringError.fileNotFound(config.catalogPath)
    }

    // Read catalog
    let catalogURL = URL(fileURLWithPath: config.catalogPath)
    let catalogData = try Data(contentsOf: catalogURL)
    var catalog = try JSONDecoder().decode(Catalog.self, from: catalogData)

    // Check if key exists
    guard let entry = catalog.strings[config.key] else {
        throw DeleteStringError.keyNotFound(config.key)
    }

    // Show what will be deleted
    let locales = entry.localizations?.keys.sorted() ?? []
    let localeList = locales.isEmpty ? "(no translations)" : locales.joined(separator: ", ")
    print("Key: \(config.key)")
    print("Translations: \(localeList)")

    if let localizations = entry.localizations {
        for locale in localizations.keys.sorted() {
            if let value = localizations[locale]?.stringUnit?.value {
                print("  \(locale): \"\(value)\"")
            } else if localizations[locale]?.variations != nil {
                print("  \(locale): (plural/device variations)")
            }
        }
    }

    if config.dryRun {
        print("")
        print("[dry-run] Would delete '\(config.key)' from catalog")
        return
    }

    // Remove the key
    catalog.strings.removeValue(forKey: config.key)

    // Write back (same approach as add-string to avoid mangling)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outputData = try encoder.encode(catalog)

    // JSONEncoder escapes forward slashes by default, but xcstrings files don't
    var outputString = String(data: outputData, encoding: .utf8)!
    outputString = outputString.replacingOccurrences(of: "\\/", with: "/")

    try outputString.write(toFile: config.catalogPath, atomically: true, encoding: .utf8)

    print("")
    print("Deleted '\(config.key)' from string catalog")
}

do {
    try run()
} catch {
    print("Error: \(error)")
    exit(1)
}
