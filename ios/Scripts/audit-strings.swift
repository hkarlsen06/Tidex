#!/usr/bin/env swift

import Foundation

// MARK: - Config

private struct Config {
    let searchPath: String
    let catalogPath: String
    let strict: Bool
    let checkHardcoded: Bool
    let checkOrphaned: Bool
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
    let key: String
    let symbolName: String
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
        (#"SecureField\(\s*"[^"]+""#, "SecureField(\"...\")")
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
        #"Text\(\s*"--"\s*\)"#
    ]

    return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
}()

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
    "/Scripts/"
]

// MARK: - Key to Symbol Name Conversion

/// Converts a String Catalog key to its generated symbol name
/// e.g., "onboarding.mfa.addToPasswords" -> "onboardingMfaAddToPasswords"
private func keyToSymbolName(_ key: String) -> String {
    let parts = key.split(separator: ".")
    guard !parts.isEmpty else { return key }

    var result = String(parts[0])
    for part in parts.dropFirst() {
        let capitalized = part.prefix(1).uppercased() + part.dropFirst()
        result += capitalized
    }
    return result
}

// MARK: - String Catalog Parsing

private func loadStringCatalogKeys(from path: String) -> Set<String> {
    guard let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: Any] else {
        print("Error: Could not load String Catalog from \(path)")
        return []
    }

    return Set(strings.keys)
}

// MARK: - File Scanning

private func findSwiftFiles(in directory: String) -> [String] {
    let fileManager = FileManager.default
    var swiftFiles: [String] = []

    guard let enumerator = fileManager.enumerator(atPath: directory) else {
        return []
    }

    while let file = enumerator.nextObject() as? String {
        guard file.hasSuffix(".swift") else { continue }

        let fullPath = (directory as NSString).appendingPathComponent(file)

        // Skip excluded paths
        if skipPaths.contains(where: { fullPath.contains($0) }) {
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
            if previewBraceDepth <= 0 && line.contains("}") {
                inPreviewBlock = false
            }
            continue // Skip all lines in preview blocks
        }

        // Skip allowed patterns
        if isAllowedLine(line) {
            continue
        }

        // Check for violations
        let range = NSRange(line.startIndex..., in: line)

        for (regex, patternName) in uiPatterns where regex.firstMatch(in: line, options: [], range: range) != nil {
            // Extract relative path
            let relativePath = path.components(separatedBy: "/TidexApp/").last ?? path

            violations.append(Violation(
                file: relativePath,
                line: lineNumber,
                code: line,
                pattern: patternName
            ))
            break // One violation per line is enough
        }
    }

    return violations
}

/// Returns all symbol references found in Swift files
private func findSymbolReferences(in directory: String) -> Set<String> {
    let swiftFiles = findSwiftFiles(in: directory)
    var references = Set<String>()

    // Patterns for localized string usage:
    // - Text(.symbolName)
    // - String(localized: .symbolName)
    // - .symbolName( for format strings that become functions
    let symbolPatterns = [
        #"Text\(\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
        #"String\(localized:\s*\.([a-zA-Z][a-zA-Z0-9_]*)"#,
        #"\.([a-zA-Z][a-zA-Z0-9_]*)\("#  // Format string functions
    ]

    let regexes = symbolPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }

    for file in swiftFiles {
        guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
            continue
        }

        for regex in regexes {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, options: [], range: range)

            for match in matches {
                if match.numberOfRanges > 1,
                   let symbolRange = Range(match.range(at: 1), in: content) {
                    references.insert(String(content[symbolRange]))
                }
            }
        }
    }

    return references
}

// MARK: - Orphaned Key Detection

private func findOrphanedKeys(catalogKeys: Set<String>, usedSymbols: Set<String>) -> [OrphanedKey] {
    var orphaned: [OrphanedKey] = []

    for key in catalogKeys {
        let symbolName = keyToSymbolName(key)

        // Skip keys that are just numbers or very short (likely placeholders or format strings)
        if key.allSatisfy({ $0.isNumber || $0 == "." || $0 == " " }) {
            continue
        }

        // Skip keys that contain format specifiers (they might be used via String(format:))
        if key.contains("%") {
            continue
        }

        // Skip keys without dots - these are likely:
        // - Single-word keys that are placeholders/symbols ("+", "---", "OK")
        // - Debug strings that don't need localization
        // Real localization keys use dot notation: "feature.subfeature.key"
        if !key.contains(".") {
            continue
        }

        // Skip admin/debug keys
        let lowercased = key.lowercased()
        if lowercased.hasPrefix("admin.") ||
           lowercased.hasPrefix("debug.") ||
           lowercased.contains("impersonate") ||
           lowercased.contains("storekit") {
            continue
        }

        // Check if the symbol is used
        if !usedSymbols.contains(symbolName) {
            orphaned.append(OrphanedKey(key: key, symbolName: symbolName))
        }
    }

    return orphaned.sorted { $0.key < $1.key }
}

// MARK: - Main

private func parseArgs() -> Config {
    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()
    // Search entire ios directory to catch usage in all targets
    let defaultSearchPath = scriptsDir
        .appendingPathComponent("..")
        .standardizedFileURL
        .path
    let defaultCatalogPath = scriptsDir
        .appendingPathComponent("../Resources/Localization/App/Localizable.xcstrings")
        .standardizedFileURL
        .path

    var searchPath = defaultSearchPath
    var catalogPath = defaultCatalogPath
    var strict = false
    var checkHardcoded = true
    var checkOrphaned = true

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--path", "-p":
            if let value = iterator.next() { searchPath = value }
        case "--catalog", "-c":
            if let value = iterator.next() { catalogPath = value }
        case "--strict", "-s":
            strict = true
        case "--hardcoded-only":
            checkOrphaned = false
        case "--orphaned-only":
            checkHardcoded = false
        case "--help", "-h":
            printHelp()
            exit(0)
        default:
            continue
        }
    }

    return Config(
        searchPath: searchPath,
        catalogPath: catalogPath,
        strict: strict,
        checkHardcoded: checkHardcoded,
        checkOrphaned: checkOrphaned
    )
}

private func printHelp() {
    print("""
    audit-strings - Audit localization strings in Swift code

    Usage: swift run audit-strings [options]

    Options:
      --path, -p <path>      Directory to scan (default: ios/)
      --catalog, -c <path>   String Catalog path (default: App/Localizable.xcstrings)
      --strict, -s           Exit with error code if issues found
      --hardcoded-only       Only check for hardcoded strings
      --orphaned-only        Only check for orphaned keys
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
      audit-strings --strict           # Exit with code 1 if issues found
    """)
}

private func run() {
    let config = parseArgs()
    var hasIssues = false

    // MARK: Check for hardcoded strings
    if config.checkHardcoded {
        print("Scanning for hardcoded strings in: \(config.searchPath)")
        print("")

        let swiftFiles = findSwiftFiles(in: config.searchPath)
        var allViolations: [Violation] = []

        for file in swiftFiles {
            let violations = scanFileForHardcodedStrings(file)
            allViolations.append(contentsOf: violations)
        }

        if allViolations.isEmpty {
            print("✓ No hardcoded strings found!")
        } else {
            hasIssues = true

            // Group by file
            let grouped = Dictionary(grouping: allViolations) { $0.file }

            print("Found \(allViolations.count) potential hardcoded strings:\n")

            for (file, violations) in grouped.sorted(by: { $0.key < $1.key }) {
                print("  \(file):")
                for violation in violations {
                    print("    L\(violation.line): \(violation.pattern)")
                }
                print("")
            }

            print("To fix: Use String Catalog symbols instead of literal strings.")
            print("  Example: Text(.settingsSaveButton) instead of Text(\"Save\")")
            print("")
            print("To add a new string:")
            print("  add-string --key \"feature.key\" --en \"English\" --nb \"Norwegian\"")
        }
        print("")
    }

    // MARK: Check for orphaned keys
    if config.checkOrphaned {
        print("Checking for orphaned keys in String Catalog...")
        print("")

        let catalogKeys = loadStringCatalogKeys(from: config.catalogPath)
        if catalogKeys.isEmpty {
            print("Warning: Could not load String Catalog or it's empty")
        } else {
            let usedSymbols = findSymbolReferences(in: config.searchPath)
            let orphaned = findOrphanedKeys(catalogKeys: catalogKeys, usedSymbols: usedSymbols)

            if orphaned.isEmpty {
                print("✓ No orphaned keys found!")
            } else {
                hasIssues = true

                print("Found \(orphaned.count) potentially orphaned keys:\n")

                // Group by prefix for readability
                let grouped = Dictionary(grouping: orphaned) { key -> String in
                    let parts = key.key.split(separator: ".")
                    return parts.first.map(String.init) ?? "other"
                }

                for (prefix, keys) in grouped.sorted(by: { $0.key < $1.key }) {
                    print("  \(prefix).*:")
                    for key in keys.prefix(10) {  // Limit output per group
                        print("    \(key.key)")
                    }
                    if keys.count > 10 {
                        print("    ... and \(keys.count - 10) more")
                    }
                    print("")
                }

                print("These keys exist in the String Catalog but weren't found in code.")
                print("They may be unused and can potentially be removed.")
                print("")
                print("Note: Some keys may be used dynamically or in other targets.")
                print("Verify before removing!")
            }
        }
    }

    if config.strict && hasIssues {
        exit(1)
    }
}

run()
