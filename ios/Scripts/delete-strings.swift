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
    let keys: [String]
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
            Usage: delete-strings --key <key> [--key <key2> ...]

            Examples:
              delete-strings --key "settings.profile.saveButton"
              delete-strings --key "btn.ok" --key "btn.cancel" --key "btn.retry"

            Options:
              --key, -k    The localization key to delete (repeatable for multiple keys)
              --catalog, -c  Optional path to xcstrings file (defaults to App catalog)
              --dry-run, -n  Show what would be deleted without modifying the file
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
    var keys: [String] = []
    var catalogPath: String?
    var dryRun = false

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--key", "-k":
            if let key = iterator.next() {
                keys.append(key)
            }
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

    guard !keys.isEmpty else {
        throw DeleteStringError.missingArguments
    }

    // Default catalog path (same as add-strings)
    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()
    let defaultCatalog = scriptsDir
        .appendingPathComponent("../Resources/Localization/App/Localizable.xcstrings")
        .standardizedFileURL
        .path

    return Config(
        keys: keys,
        catalogPath: catalogPath ?? defaultCatalog,
        dryRun: dryRun
    )
}

private func printEntry(key: String, entry: CatalogEntry) {
    let locales = entry.localizations?.keys.sorted() ?? []
    let localeList = locales.isEmpty ? "(no translations)" : locales.joined(separator: ", ")
    print("  \(key)  [\(localeList)]")

    if let localizations = entry.localizations {
        for locale in localizations.keys.sorted() {
            if let value = localizations[locale]?.stringUnit?.value {
                print("    \(locale): \"\(value)\"")
            } else if localizations[locale]?.variations != nil {
                print("    \(locale): (plural/device variations)")
            }
        }
    }
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

    // Validate all keys exist first
    var notFound: [String] = []
    for key in config.keys {
        if catalog.strings[key] == nil {
            notFound.append(key)
        }
    }

    if !notFound.isEmpty {
        print("Keys not found in catalog:")
        for key in notFound {
            print("  \(key)")
        }
        if notFound.count < config.keys.count {
            print("")
            print("Aborting — no keys were deleted. Fix the missing keys and try again.")
        }
        exit(1)
    }

    // Show what will be deleted
    for key in config.keys {
        if let entry = catalog.strings[key] {
            printEntry(key: key, entry: entry)
        }
    }

    if config.dryRun {
        print("")
        print("[dry-run] Would delete \(config.keys.count) key(s) from catalog")
        return
    }

    // Remove all keys
    for key in config.keys {
        catalog.strings.removeValue(forKey: key)
    }

    // Write back (same approach as add-strings to avoid mangling)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outputData = try encoder.encode(catalog)

    var outputString = String(data: outputData, encoding: .utf8)!
    outputString = outputString.replacingOccurrences(of: "\\/", with: "/")

    try outputString.write(toFile: config.catalogPath, atomically: true, encoding: .utf8)

    print("")
    print("Deleted \(config.keys.count) key(s) from string catalog")
}

do {
    try run()
} catch {
    print("Error: \(error)")
    exit(1)
}
