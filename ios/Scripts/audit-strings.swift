#!/usr/bin/env swift
import Foundation

// swiftlint:disable no_direct_print no_raw_localization_keys

// MARK: - Config

private struct Config {
  let searchPath: String
  let catalogPaths: [String]
  let strict: Bool
  let checkHardcoded: Bool
  let checkErrorDescriptions: Bool
  let checkOrphaned: Bool
  let jsonOutput: Bool
  let removeOrphaned: Bool
}

// MARK: - Models

private struct Violation: CustomStringConvertible {
  let file: String
  let line: Int
  let code: String
  let pattern: String

  var description: String {
    "\(file):\(line): \(pattern) - \(code.trimmingCharacters(in: .whitespaces))"
  }
}

private struct OrphanedKey {
  let catalogPath: String
  let key: String
  let symbolName: String
  let reason: String
}

private struct CatalogEntry {
  let key: String
  let extractionState: String?
}

// MARK: - Patterns to detect hardcoded strings

// SwiftUI views that commonly contain user-visible strings
private let uiPatterns: [(regex: NSRegularExpression, name: String)] = {
  let patterns: [(String, String)] = [
    // Text with literal string (not a symbol like .keyName)
    (#"Text\(\s*"[^"]+""#, "Text(\"...\")"),

    // Label with literal title
    (#"Label\(\s*"[^"]+""#, "Label(\"...\")"),

    // Button with literal label
    (#"Button\(\s*"[^"]+""#, "Button(\"...\")"),

    // NavigationTitle with literal
    (#"\.navigationTitle\(\s*"[^"]+""#, ".navigationTitle(\"...\")"),

    // Alert title/message with literal
    (#"\.alert\(\s*"[^"]+""#, ".alert(\"...\")"),

    // Section header with literal
    (#"Section\(\s*"[^"]+""#, "Section(\"...\")"),

    // Tab item label
    (#"\.tabItem\s*\{[^}]*Text\(\s*"[^"]+""#, ".tabItem { Text(\"...\") }"),

    // Toolbar item label
    (#"ToolbarItem[^}]*Label\(\s*"[^"]+""#, "ToolbarItem Label(\"...\")"),

    // Placeholder text
    (#"\.textFieldStyle[^)]*placeholder:\s*"[^"]+""#, "placeholder: \"...\""),

    // TextField/SecureField with literal prompt
    (#"TextField\(\s*"[^"]+""#, "TextField(\"...\")"),
    (#"SecureField\(\s*"[^"]+""#, "SecureField(\"...\")"),
  ]

  return patterns.compactMap { pattern, name -> (NSRegularExpression, String)? in
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }
    return (regex, name)
  }
}()

// Patterns that are OK (not violations)
private let allowedPatterns: [NSRegularExpression] = {
  let patterns = [
    // Empty strings and whitespace-only
    #"Text\(\s*""\s*\)"#,
    #"Text\(\s*"\s+"\s*\)"#,

    // String interpolation (likely dynamic)
    #"Text\(\s*".*\\.*""#,

    // SF Symbols
    #"Image\(systemName:\s*"[^"]+""#,
    #"Label\([^,]+,\s*systemImage:\s*"[^"]+""#,

    // Asset names
    #"Image\(\s*"[^"]+""#,
    #"Color\(\s*"[^"]+""#,

    // Identifiers/keys (no spaces, looks like code)
    #"Text\(\s*"[a-zA-Z0-9_.]+"\s*\)"#,

    // URLs
    #""https?://[^"]+""#,

    // Format specifiers (likely used with String(format:))
    #""%[^"]*[dsfx@]"#,

    // Debug/preview strings
    #"#Preview\s*\{"#,
    #"preview"#,

    // Comments
    #"^\s*//"#,

    // String(localized:) - proper localization
    #"String\(localized:"#,

    // LocalizedStringKey
    #"LocalizedStringKey"#,

    // Universal symbols and separators (not localizable)
    #"Text\(\s*"[·•−+–→—|%]"\s*\)"#,

    // Time/number format hints in TextFields (e.g., "00:00", "000000", "123456")
    #"TextField\(\s*"[0-9:]+""#,

    // Country codes (e.g., "+47")
    #"Text\(\s*"\+\d+""#,

    // System button labels (OK, Cancel - handled by iOS)
    #"Button\(\s*"OK""#,

    // Em dash for "no value" placeholder
    #"Text\(\s*"—"\s*\)"#,
    #"Text\(\s*"---"\s*\)"#,

    // Time/data placeholder formats
    #"Text\(\s*"--:--"\s*\)"#,
    #"Text\(\s*"--"\s*\)"#,
  ]

  return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
}()

private let rawLocalizationKeyPatterns: [(regex: NSRegularExpression, name: String)] = {
  let patterns: [(String, String)] = [
    (#"String\(localized:\s*"[^"]+""#, "String(localized: \"...\")"),
    (#"LocalizedStringResource\(\s*"[^"]+""#, "LocalizedStringResource(\"...\")"),
    (#"LocalizedStringKey\("#, "LocalizedStringKey(...)"),
    (#"NSLocalizedString\(\s*"[^"]+""#, "NSLocalizedString(\"...\")"),
    (#"Text\(\s*"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_:-]+)+"\s*\)"#, "Text(\"dot.key\")"),
    (#"Text\(\s*"[^"]+"\s*,\s*tableName:"#, "Text(\"...\", tableName:)"),
  ]

  return patterns.compactMap { pattern, name -> (NSRegularExpression, String)? in
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }
    return (regex, name)
  }
}()

private let rawErrorDescriptionReturnPattern = try? NSRegularExpression(
  pattern: #"\breturn\s+"[^"]*[A-Za-z][^"]*""#,
  options: []
)

// Files/directories to skip
private let skipPaths = [
  "/Preview Content/",
  "/Previews/",
  "Tests.swift",
  "Mock",
  ".build/",
  "DerivedData/",
  "/Admin/",
  "DebugView.swift",
  "/Scripts/",
]

// MARK: - Key to Symbol Name Conversion

/// Converts a String Catalog key to its generated symbol name
/// e.g., "onboarding.mfa.addToPasswords" -> "onboardingMfaAddToPasswords"
/// e.g., "onboarding.paycheck.base_pay" -> "onboardingPaycheckBasePay"
private func keyToSymbolName(_ key: String) -> String {
  // Split by dots first, then handle underscores within each part
  let dotParts = key.split(separator: ".")
  guard !dotParts.isEmpty else { return key }

  var result = ""
  for (index, dotPart) in dotParts.enumerated() {
    // Split each dot-part by underscores
    let underscoreParts = dotPart.split(separator: "_")
    for (subIndex, part) in underscoreParts.enumerated() {
      if index == 0, subIndex == 0 {
        // First part stays as-is (preserves original casing)
        result += String(part)
      } else {
        // Subsequent parts: capitalize first letter, keep rest as-is
        result += part.prefix(1).uppercased() + part.dropFirst()
      }
    }
  }
  return result
}

// MARK: - String Catalog Parsing

private func loadStringCatalogKeys(from path: String) -> Set<String> {
  Set(loadStringCatalogEntries(from: path).map(\.key))
}

private func findStringCatalogs(in directory: String) -> [String] {
  let fileManager = FileManager.default
  guard let enumerator = fileManager.enumerator(atPath: directory) else {
    return []
  }

  var catalogs: [String] = []
  while let file = enumerator.nextObject() as? String {
    guard file.hasSuffix(".xcstrings") else { continue }
    catalogs.append((directory as NSString).appendingPathComponent(file))
  }
  return catalogs.sorted()
}

private func loadStringCatalogEntries(from path: String) -> [CatalogEntry] {
  guard let data = FileManager.default.contents(atPath: path),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let strings = json["strings"] as? [String: Any]
  else {
    print("Error: Could not load String Catalog from \(path)")
    return []
  }

  return strings.map { key, value in
    let entry = value as? [String: Any]
    return CatalogEntry(key: key, extractionState: entry?["extractionState"] as? String)
  }
}

// MARK: - File Scanning

private func findSwiftFiles(in directory: String, includeSkippedPaths: Bool = false) -> [String] {
  let fileManager = FileManager.default
  var swiftFiles: [String] = []

  guard let enumerator = fileManager.enumerator(atPath: directory) else {
    return []
  }

  while let file = enumerator.nextObject() as? String {
    guard file.hasSuffix(".swift") else { continue }

    let fullPath = (directory as NSString).appendingPathComponent(file)

    // Skip excluded paths
    if !includeSkippedPaths, skipPaths.contains(where: { fullPath.contains($0) }) {
      continue
    }

    swiftFiles.append(fullPath)
  }

  return swiftFiles
}

private func isAllowedLine(_ line: String) -> Bool {
  let range = NSRange(line.startIndex..., in: line)
  return allowedPatterns.contains { regex in
    regex.firstMatch(in: line, options: [], range: range) != nil
  }
}

private func scanFileForHardcodedStrings(_ path: String) -> [Violation] {
  guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
    return []
  }

  var violations: [Violation] = []
  let lines = content.components(separatedBy: .newlines)

  // Track #Preview blocks to skip them
  var inPreviewBlock = false
  var previewBraceDepth = 0

  for (index, line) in lines.enumerated() {
    let lineNumber = index + 1

    // Check if entering a #Preview block
    if line.contains("#Preview") {
      inPreviewBlock = true
      previewBraceDepth = 0
    }

    // Track brace depth when in preview block
    if inPreviewBlock {
      previewBraceDepth += line.filter { $0 == "{" }.count
      previewBraceDepth -= line.filter { $0 == "}" }.count

      // Exit preview block when braces balance (and we've seen at least one open brace)
      if previewBraceDepth <= 0, line.contains("}") {
        inPreviewBlock = false
      }
      continue  // Skip all lines in preview blocks
    }

    // Skip allowed patterns
    if isAllowedLine(line) {
      continue
    }

    // Check for violations
    let range = NSRange(line.startIndex..., in: line)

    for (regex, patternName) in uiPatterns
    where regex.firstMatch(in: line, options: [], range: range) != nil {
      // Extract relative path
      let relativePath = path.components(separatedBy: "/TidexApp/").last ?? path

      violations.append(
        Violation(
          file: relativePath,
          line: lineNumber,
          code: line,
          pattern: patternName
        ))
      break  // One violation per line is enough
    }
  }

  return violations
}

private func scanFileForRawLocalizationKeys(_ path: String) -> [Violation] {
  guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
    return []
  }

  var violations: [Violation] = []
  let lines = content.components(separatedBy: .newlines)

  for (index, line) in lines.enumerated() {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.hasPrefix("//") else { continue }

    let range = NSRange(line.startIndex..., in: line)
    for (regex, patternName) in rawLocalizationKeyPatterns
    where regex.firstMatch(in: line, options: [], range: range) != nil {
      let relativePath = path.components(separatedBy: "/ios/").last ?? path
      violations.append(
        Violation(
          file: relativePath,
          line: index + 1,
          code: line,
          pattern: patternName
        ))
      break
    }
  }

  return violations
}

private func scanFileForRawErrorDescriptions(_ path: String) -> [Violation] {
  guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
    return []
  }

  var violations: [Violation] = []
  let lines = content.components(separatedBy: .newlines)
  var isInsideErrorDescription = false
  var braceDepth = 0

  for (index, line) in lines.enumerated() {
    if !isInsideErrorDescription, line.contains("var errorDescription: String?") {
      isInsideErrorDescription = true
      braceDepth = 0
    }

    guard isInsideErrorDescription else { continue }

    braceDepth += line.filter { $0 == "{" }.count
    braceDepth -= line.filter { $0 == "}" }.count

    let range = NSRange(line.startIndex..., in: line)
    if rawErrorDescriptionReturnPattern?.firstMatch(in: line, options: [], range: range) != nil {
      let relativePath = path.components(separatedBy: "/ios/").last ?? path
      violations.append(
        Violation(
          file: relativePath,
          line: index + 1,
          code: line,
          pattern: "LocalizedError.errorDescription raw string"
        ))
    }

    if braceDepth <= 0, line.contains("}") {
      isInsideErrorDescription = false
    }
  }

  return violations
}

/// Result of scanning for localization references
private struct LocalizationReferences {
  var symbols: Set<String>  // Symbol names like "dashboardTitle"
  var directKeys: Set<String>  // Direct keys like "common.cancel"
  var dynamicPrefixes: Set<String>  // Prefixes like "onboarding.paycheck.industry."
}

private func extractCaptures(from content: String, using regexes: [NSRegularExpression]) -> Set<
  String
> {
  var results: Set<String> = []
  let range = NSRange(content.startIndex..., in: content)
  for regex in regexes {
    for match in regex.matches(in: content, options: [], range: range) {
      if match.numberOfRanges > 1,
        let captureRange = Range(match.range(at: 1), in: content)
      {
        results.insert(String(content[captureRange]))
      }
    }
  }
  return results
}

/// Returns all localization references found in Swift files
private func findLocalizationReferences(in directory: String) -> LocalizationReferences {
  let swiftFiles = findSwiftFiles(in: directory, includeSkippedPaths: true)
  var result = LocalizationReferences(symbols: [], directKeys: [], dynamicPrefixes: [])

  let symbolRegexes = [
    #"Text\(\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
    #"String\(localized:\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
    #"\.([a-zA-Z][a-zA-Z0-9_]*)\("#,
    #"Key:\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
    #"\?\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
    #"\s[:?]\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
    #"return\s+\.([a-zA-Z][a-zA-Z0-9_]*)"#,
    #":\s+\.([a-zA-Z][a-zA-Z0-9_]*)\s*[,\)]"#,
    #"=\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
    #"\(\s*\.([a-zA-Z][a-zA-Z0-9_]*)\s*\)"#,
    #"(?:^|\n)\s*\.([a-zA-Z][a-zA-Z0-9_]*)\s*(?:\n|$)"#,
  ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

  let directKeyRegexes = [
    #"NSLocalizedString\(\s*"([a-zA-Z][a-zA-Z0-9_.]+)""#,
    #"String\(localized:\s*"([a-zA-Z][a-zA-Z0-9_.]+)""#,
    #"Text\(\s*"([a-zA-Z][a-zA-Z0-9_.]+)"\s*,\s*tableName:"#,
    #"LocalizedStringResource\(\s*"([a-zA-Z][a-zA-Z0-9_.]+)""#,
    #"LocalizedStringKey\(\s*"([a-zA-Z][a-zA-Z0-9_.]+)""#,
    #""([a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+)""#,
  ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

  let dynamicKeyRegexes = [
    #"String\.LocalizationValue\(\s*"([a-zA-Z][a-zA-Z0-9_.]+)\\\("#,
    #"=\s*"([a-zA-Z][a-zA-Z0-9_.]+)\\\("#,
  ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

  for file in swiftFiles {
    guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
    result.symbols.formUnion(extractCaptures(from: content, using: symbolRegexes))
    result.directKeys.formUnion(extractCaptures(from: content, using: directKeyRegexes))
    result.dynamicPrefixes.formUnion(extractCaptures(from: content, using: dynamicKeyRegexes))
  }

  return result
}

// MARK: - Orphaned Key Detection

private func findOrphanedKeys(
  catalogPath: String,
  catalogEntries: [CatalogEntry],
  references: LocalizationReferences
)
  -> [OrphanedKey]
{
  var orphaned: [OrphanedKey] = []

  for entry in catalogEntries {
    let key = entry.key
    let symbolName = keyToSymbolName(key)

    if entry.extractionState == "stale" {
      orphaned.append(
        OrphanedKey(
          catalogPath: catalogPath,
          key: key,
          symbolName: symbolName,
          reason: "stale"
        ))
      continue
    }

    // Skip keys that are just numbers or very short (likely placeholders or format strings)
    if key.allSatisfy({ $0.isNumber || $0 == "." || $0 == " " }) {
      continue
    }

    // Skip keys that contain format specifiers (they might be used via String(format:))
    if key.contains("%") {
      continue
    }

    // Skip keys that are not dot-notation identifiers. These are likely:
    // - Single-word keys that are placeholders/symbols ("+", "---", "OK")
    // - Sentence-style legacy keys that contain punctuation periods
    // - Debug strings that don't need localization
    // Real localization keys use dot notation: "feature.subfeature.key"
    let keyParts = key.split(separator: ".", omittingEmptySubsequences: false)
    if keyParts.count < 2
      || keyParts.contains(where: {
        $0.isEmpty
          || !$0.allSatisfy { character in
            character == "_" || character.isLetter || character.isNumber
          }
      })
    {
      continue
    }

    // Skip admin/debug keys
    let lowercased = key.lowercased()
    if lowercased.hasPrefix("admin.") || lowercased.hasPrefix("debug.")
      || lowercased.contains("impersonate") || lowercased.contains("storekit")
    {
      continue
    }

    // Check if the key is used via any method:
    // 1. Symbol reference (e.g., .dashboardTitle)
    if references.symbols.contains(symbolName) {
      continue
    }

    // 2. Direct key reference (e.g., NSLocalizedString("common.cancel", ...))
    if references.directKeys.contains(key) {
      continue
    }

    // 3. Dynamic prefix (e.g., "onboarding.paycheck.industry." matches "onboarding.paycheck.industry.retail")
    let matchesDynamicPrefix = references.dynamicPrefixes.contains { prefix in
      key.hasPrefix(prefix)
    }
    if matchesDynamicPrefix {
      continue
    }

    orphaned.append(
      OrphanedKey(
        catalogPath: catalogPath,
        key: key,
        symbolName: symbolName,
        reason: "missing reference"
      ))
  }

  return orphaned.sorted { $0.key < $1.key }
}

// MARK: - Catalog Modification

/// Removes orphaned keys from the String Catalog
private func removeKeysFromCatalog(keys: [String], catalogPath: String) -> Bool {
  guard let data = FileManager.default.contents(atPath: catalogPath),
    var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    var strings = json["strings"] as? [String: Any]
  else {
    print("Error: Could not load String Catalog")
    return false
  }

  var removedCount = 0
  for key in keys where strings.removeValue(forKey: key) != nil {
    removedCount += 1
  }

  json["strings"] = strings

  let serializationOptions: JSONSerialization.WritingOptions = [
    .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
  ]
  guard
    let updatedData = try? JSONSerialization.data(
      withJSONObject: json, options: serializationOptions)
  else {
    print("Error: Could not serialize updated catalog")
    return false
  }

  do {
    try updatedData.write(to: URL(fileURLWithPath: catalogPath))
    print("✓ Removed \(removedCount) orphaned keys from String Catalog")
    return true
  } catch {
    print("Error: Could not write updated catalog: \(error)")
    return false
  }
}

// MARK: - Main

private func parseArgs() -> Config {
  let scriptURL = URL(fileURLWithPath: #filePath)
  let scriptsDir = scriptURL.deletingLastPathComponent()
  // Search entire ios directory to catch usage in all targets
  let defaultSearchPath =
    scriptsDir
    .appendingPathComponent("..")
    .standardizedFileURL
    .path
  let defaultCatalogRoot =
    scriptsDir
    .appendingPathComponent("../Resources/Localization")
    .standardizedFileURL
    .path

  var searchPath = defaultSearchPath
  var catalogPaths: [String] = []
  var strict = false
  var checkHardcoded = true
  var checkErrorDescriptions = false
  var checkOrphaned = true
  var jsonOutput = false
  var removeOrphaned = false

  var iterator = CommandLine.arguments.dropFirst().makeIterator()
  while let arg = iterator.next() {
    switch arg {
    case "--path", "-p":
      searchPath = iterator.next() ?? searchPath

    case "--catalog", "-c":
      if let catalogPath = iterator.next() {
        catalogPaths.append(catalogPath)
      }

    case "--strict", "-s": strict = true
    case "--hardcoded-only": checkOrphaned = false

    case "--error-descriptions":
      checkHardcoded = false
      checkErrorDescriptions = true
      checkOrphaned = false

    case "--orphaned-only": checkHardcoded = false
    case "--json": jsonOutput = true

    case "--remove":
      removeOrphaned = true
      checkHardcoded = false

    case "--help", "-h":
      printHelp()
      exit(0)

    default: continue
    }
  }

  if catalogPaths.isEmpty {
    catalogPaths = findStringCatalogs(in: defaultCatalogRoot)
  }

  return Config(
    searchPath: searchPath,
    catalogPaths: catalogPaths,
    strict: strict,
    checkHardcoded: checkHardcoded,
    checkErrorDescriptions: checkErrorDescriptions,
    checkOrphaned: checkOrphaned,
    jsonOutput: jsonOutput,
    removeOrphaned: removeOrphaned
  )
}

private func printHelp() {
  print(
    """
    audit-strings - Audit localization strings in Swift code

    Usage: swift run audit-strings [options]

    Options:
      --path, -p <path>      Directory to scan (default: ios/)
      --catalog, -c <path>   String Catalog path. May be repeated.
                              Default: every .xcstrings file under Resources/Localization.
      --strict, -s           Exit with error code if issues found
      --hardcoded-only       Only check for hardcoded strings
      --error-descriptions   Only check raw LocalizedError.errorDescription strings
      --orphaned-only        Only check for orphaned keys
      --json                 Output orphaned keys as JSON array
      --remove               Remove orphaned keys from the String Catalog
      --help, -h             Show this help

    This script performs two types of checks:

    1. HARDCODED STRINGS
       Finds hardcoded user-visible strings that should be localized:
       - Text("literal string")
       - Label("literal string", ...)
       - Button("literal string") { ... }
       - .navigationTitle("literal string")

    2. ORPHANED KEYS
       Finds keys in the String Catalog that aren't used in code.
       These may be:
       - Leftover from deleted features
       - Typos in key names
       - Keys that should be cleaned up

    Examples:
      audit-strings                    # Run all checks
      audit-strings --orphaned-only    # Only find unused keys
      audit-strings --json             # Output orphaned keys as JSON
      audit-strings --remove           # Remove orphaned keys from catalog
      audit-strings --strict           # Exit with code 1 if issues found
    """)
}

private func checkRawErrorDescriptions(config: Config) -> Bool {
  print("Scanning for raw LocalizedError.errorDescription strings in: \(config.searchPath)\n")

  let findings = findSwiftFiles(in: config.searchPath)
    .flatMap { scanFileForRawErrorDescriptions($0) }

  guard !findings.isEmpty else {
    print("✓ No raw LocalizedError.errorDescription strings found!\n")
    return false
  }

  let grouped = Dictionary(grouping: findings) { $0.file }
  print("Found \(findings.count) raw LocalizedError.errorDescription strings:\n")
  for (file, violations) in grouped.sorted(by: { $0.key < $1.key }) {
    print("  \(file):")
    for violation in violations { print("    L\(violation.line): \(violation.pattern)") }
    print("")
  }
  print("To fix: return localized symbols from user-facing error descriptions.")
  print("  Example: return String(localized: .commonNetworkError)\n")
  return true
}

private func checkHardcodedStrings(config: Config) -> Bool {
  print("Scanning for hardcoded strings in: \(config.searchPath)\n")

  let allViolations = findSwiftFiles(in: config.searchPath)
    .flatMap { scanFileForHardcodedStrings($0) }
  let rawLocalizationViolations = findSwiftFiles(in: config.searchPath, includeSkippedPaths: true)
    .filter { !$0.contains("/Scripts/") }
    .flatMap { scanFileForRawLocalizationKeys($0) }
  let allFindings = allViolations + rawLocalizationViolations

  guard !allFindings.isEmpty else {
    print("✓ No hardcoded strings found!\n")
    return false
  }

  let grouped = Dictionary(grouping: allFindings) { $0.file }
  print("Found \(allFindings.count) potential hardcoded strings:\n")
  for (file, violations) in grouped.sorted(by: { $0.key < $1.key }) {
    print("  \(file):")
    for violation in violations { print("    L\(violation.line): \(violation.pattern)") }
    print("")
  }
  print("To fix: Use String Catalog symbols instead of literal strings.")
  print("  Example: Text(.settingsSaveButton) instead of Text(\"Save\")")
  print("\nTo add a new string:")
  print(
    "  ./scripts/xcstrings-set ios/Resources/Localization/App/Localizable.xcstrings "
      + "feature.key --comment \"Translator context\" --en \"English\" --nb \"Norwegian\"\n"
  )
  return true
}

private func printOrphanedKeysHumanReadable(
  _ orphaned: [OrphanedKey],
  catalogPath: String
) {
  print("\(catalogPath)")
  print("Found \(orphaned.count) potentially orphaned or stale keys:\n")
  let grouped = Dictionary(grouping: orphaned) { key -> String in
    if key.reason == "stale" {
      return "stale"
    }
    let parts = key.key.split(separator: ".")
    return parts.first.map(String.init) ?? "other"
  }
  for (prefix, keys) in grouped.sorted(by: { $0.key < $1.key }) {
    print("  \(prefix).*:")
    for key in keys.prefix(10) { print("    \(key.key)") }
    if keys.count > 10 { print("    ... and \(keys.count - 10) more") }
    print("")
  }
  print(
    "These keys exist in the String Catalog but weren't found in code, or Xcode marked them stale.")
  print("They may be unused and can potentially be removed.")
  print("\nNote: Some keys may be used dynamically or in other targets.")
  print("Verify before removing!")
}

private func checkOrphanedKeys(config: Config) -> Bool {
  if !config.jsonOutput, !config.removeOrphaned {
    print("Checking for orphaned keys in String Catalogs...\n")
  }

  guard !config.catalogPaths.isEmpty else {
    print("Warning: Could not find any String Catalogs")
    return false
  }

  let references = findLocalizationReferences(in: config.searchPath)
  var orphanedByCatalog: [(catalogPath: String, orphaned: [OrphanedKey])] = []
  for catalogPath in config.catalogPaths {
    let catalogEntries = loadStringCatalogEntries(from: catalogPath)
    guard !catalogEntries.isEmpty else {
      print("Warning: Could not load String Catalog or it's empty: \(catalogPath)")
      continue
    }

    let orphaned = findOrphanedKeys(
      catalogPath: catalogPath,
      catalogEntries: catalogEntries,
      references: references
    )
    orphanedByCatalog.append((catalogPath: catalogPath, orphaned: orphaned))
  }

  let allOrphaned = orphanedByCatalog.flatMap(\.orphaned)

  guard !allOrphaned.isEmpty else {
    print(config.jsonOutput ? "[]" : "✓ No orphaned keys found!")
    return false
  }

  if config.jsonOutput {
    let jsonObject: Any
    if config.catalogPaths.count == 1 {
      jsonObject = allOrphaned.map(\.key)
    } else {
      jsonObject = allOrphaned.map { key in
        [
          "catalog": key.catalogPath,
          "key": key.key,
          "reason": key.reason,
        ]
      }
    }

    if let jsonData = try? JSONSerialization.data(
      withJSONObject: jsonObject,
      options: [
        .prettyPrinted, .sortedKeys,
      ]), let jsonString = String(data: jsonData, encoding: .utf8)
    {
      print(jsonString)
    }
  } else if config.removeOrphaned {
    print("Removing \(allOrphaned.count) orphaned keys from String Catalogs...")
    for (catalogPath, orphaned) in orphanedByCatalog where !orphaned.isEmpty {
      _ = removeKeysFromCatalog(keys: orphaned.map(\.key), catalogPath: catalogPath)
    }
  } else {
    for (catalogPath, orphaned) in orphanedByCatalog where !orphaned.isEmpty {
      printOrphanedKeysHumanReadable(orphaned, catalogPath: catalogPath)
      print("")
    }
  }
  return true
}

private func run() {
  let config = parseArgs()
  var hasIssues = false

  if config.checkHardcoded {
    hasIssues = checkHardcodedStrings(config: config) || hasIssues
  }
  if config.checkErrorDescriptions {
    hasIssues = checkRawErrorDescriptions(config: config) || hasIssues
  }
  if config.checkOrphaned {
    hasIssues = checkOrphanedKeys(config: config) || hasIssues
  }

  if config.strict, hasIssues {
    exit(1)
  }
}

run()
// swiftlint:enable no_direct_print no_raw_localization_keys
