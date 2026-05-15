#!/usr/bin/env swift

import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

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
  case invalidUTF8Encoding
  case incompleteEntry(String)
  case lockFileOpenFailed(String)
  case lockFailed(String)
  case invalidCatalogStructure(String)
  case invalidKey(String)

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
    case .invalidUTF8Encoding:
      return "Failed to convert output data to UTF-8 string"
    case .incompleteEntry(let key):
      return
        "Incomplete entry for key '\(key)': both --en and --nb values are required after each --key"
    case .lockFileOpenFailed(let path):
      return "Failed to open lock file at \(path)"
    case .lockFailed(let path):
      return "Failed to acquire lock for \(path)"
    case .invalidCatalogStructure(let reason):
      return "Invalid catalog structure: \(reason)"
    case .invalidKey(let reason):
      return "Invalid key: \(reason)"
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
    guard let english = currentEn, let norwegian = currentNb else {
      throw AddStringError.incompleteEntry(key)
    }
    try validateKey(key)
    entries.append(StringEntry(key: key, englishValue: english, norwegianValue: norwegian))
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
  let defaultCatalog =
    scriptsDir
    .appendingPathComponent("../Resources/Localization/App/Localizable.xcstrings")
    .standardizedFileURL
    .path

  return Config(
    entries: entries,
    catalogPath: catalogPath ?? defaultCatalog
  )
}

private func validateKey(_ key: String) throws {
  if key.contains("_") {
    throw AddStringError.invalidKey(
      "'\(key)' contains an underscore. Use dot-separated camelCase segments instead, e.g. dashboard.payrollDetails.totalGross."
    )
  }
}

private enum EntryResult {
  case added
  case needsManualUpdate
  case skipped
}

private func processEntry(_ entry: StringEntry, in catalog: inout Catalog) -> EntryResult {
  if let existingEntry = catalog.strings[entry.key] {
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

    guard !added.isEmpty else {
      print("  Skipped '\(entry.key)' (already has en + nb translations)")
      return .skipped
    }

    print(
      "  Needs manual update '\(entry.key)' — missing: \(added.joined(separator: ", ")) (skipped to avoid full catalog rewrite)"
    )
    return .needsManualUpdate
  }

  let newEntry = CatalogEntry(
    extractionState: "manual",
    localizations: [
      "en": CatalogLocalization(
        stringUnit: CatalogStringUnit(state: "translated", value: entry.englishValue)
      ),
      "nb": CatalogLocalization(
        stringUnit: CatalogStringUnit(state: "translated", value: entry.norwegianValue)
      ),
    ]
  )
  catalog.strings[entry.key] = newEntry
  print("  Added '\(entry.key)'")
  return .added
}

private struct StringsObjectBounds {
  let openBrace: String.Index
  let closeBrace: String.Index
  let hasEntries: Bool
}

private func quoteJSONString(_ value: String) throws -> String {
  let data = try JSONEncoder().encode(value)
  guard let encoded = String(data: data, encoding: .utf8) else {
    throw AddStringError.invalidUTF8Encoding
  }
  return encoded.replacingOccurrences(of: "\\/", with: "/")
}

private func entryBlock(for entry: StringEntry) throws -> String {
  let key = try quoteJSONString(entry.key)
  let english = try quoteJSONString(entry.englishValue)
  let norwegian = try quoteJSONString(entry.norwegianValue)

  return """
        \(key) : {
          "extractionState" : "manual",
          "localizations" : {
            "en" : {
              "stringUnit" : {
                "state" : "translated",
                "value" : \(english)
              }
            },
            "nb" : {
              "stringUnit" : {
                "state" : "translated",
                "value" : \(norwegian)
              }
            }
          }
        }
    """
}

private func locateStringsObjectBounds(in contents: String) throws -> StringsObjectBounds {
  guard let stringsKeyRange = contents.range(of: "\"strings\"") else {
    throw AddStringError.invalidCatalogStructure("missing top-level 'strings' object")
  }

  guard let openBrace = contents[stringsKeyRange.upperBound...].firstIndex(of: "{") else {
    throw AddStringError.invalidCatalogStructure("missing opening brace for 'strings'")
  }

  var index = contents.index(after: openBrace)
  var depth = 1
  var isInsideString = false
  var isEscaping = false

  while index < contents.endIndex {
    let char = contents[index]

    if isInsideString {
      if isEscaping {
        isEscaping = false
      } else if char == "\\" {
        isEscaping = true
      } else if char == "\"" {
        isInsideString = false
      }
    } else {
      if char == "\"" {
        isInsideString = true
      } else if char == "{" {
        depth += 1
      } else if char == "}" {
        depth -= 1
        if depth == 0 {
          let innerContents = contents[contents.index(after: openBrace)..<index]
          let hasEntries = innerContents.contains { !$0.isWhitespace }
          return StringsObjectBounds(
            openBrace: openBrace, closeBrace: index, hasEntries: hasEntries)
        }
      }
    }

    index = contents.index(after: index)
  }

  throw AddStringError.invalidCatalogStructure("unterminated 'strings' object")
}

private func appendEntriesWithoutReordering(_ entries: [StringEntry], to path: String) throws {
  guard !entries.isEmpty else { return }

  var contents = try String(contentsOfFile: path, encoding: .utf8)
  let bounds = try locateStringsObjectBounds(in: contents)

  let closingLineStart =
    contents[..<bounds.closeBrace].lastIndex(of: "\n")
    .map { contents.index(after: $0) } ?? bounds.closeBrace
  var insertionIndex = closingLineStart

  if bounds.hasEntries {
    let prefix = contents[..<closingLineStart]
    guard let lastNonWhitespace = prefix.lastIndex(where: { !$0.isWhitespace }) else {
      throw AddStringError.invalidCatalogStructure("could not locate last entry in 'strings'")
    }
    let commaInsertionIndex = contents.index(after: lastNonWhitespace)
    contents.insert(",", at: commaInsertionIndex)
    if commaInsertionIndex < insertionIndex {
      insertionIndex = contents.index(after: insertionIndex)
    }
  }

  let blocks = try entries.map(entryBlock).joined(separator: ",\n")
  contents.insert(contentsOf: "\(blocks)\n", at: insertionIndex)
  try contents.write(toFile: path, atomically: true, encoding: .utf8)
}

private func withExclusiveCatalogLock<T>(catalogPath: String, body: () throws -> T) throws -> T {
  let lockPath = "\(catalogPath).lock"
  let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
  guard fd >= 0 else {
    throw AddStringError.lockFileOpenFailed(lockPath)
  }

  defer {
    _ = close(fd)
  }

  guard flock(fd, LOCK_EX) == 0 else {
    throw AddStringError.lockFailed(lockPath)
  }
  defer {
    _ = flock(fd, LOCK_UN)
  }

  return try body()
}

private func run() throws {
  let config = try parseArgs()

  guard FileManager.default.fileExists(atPath: config.catalogPath) else {
    throw AddStringError.fileNotFound(config.catalogPath)
  }

  var addedCount = 0
  var manualUpdateCount = 0
  var addedEntries: [StringEntry] = []

  try withExclusiveCatalogLock(catalogPath: config.catalogPath) {
    let catalogURL = URL(fileURLWithPath: config.catalogPath)
    let catalogData = try Data(contentsOf: catalogURL)
    var catalog = try JSONDecoder().decode(Catalog.self, from: catalogData)

    for entry in config.entries {
      switch processEntry(entry, in: &catalog) {
      case .added:
        addedCount += 1
        addedEntries.append(entry)
      case .needsManualUpdate:
        manualUpdateCount += 1
      case .skipped: break
      }
    }

    if addedCount > 0 {
      try appendEntriesWithoutReordering(addedEntries, to: config.catalogPath)
    }
  }

  print("")
  var parts: [String] = []
  if addedCount > 0 { parts.append("\(addedCount) added") }
  if manualUpdateCount > 0 { parts.append("\(manualUpdateCount) needs manual update") }
  if !parts.isEmpty {
    print("Done: \(parts.joined(separator: ", "))")
  } else {
    print("Done: no changes")
  }

  if manualUpdateCount > 0 {
    print(
      "Note: Existing keys with missing locales are not auto-updated to avoid rewriting entire .xcstrings files."
    )
  }

  if addedCount > 0 {
    print("\nUsage in code:")
    for entry in config.entries {
      print("  Text(.\(generateSymbolName(from: entry.key)))")
    }
    print("\nRemember to run translate-xcstrings.mjs to add other languages!")
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
