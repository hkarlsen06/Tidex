#!/usr/bin/env swift

import Foundation

// MARK: - Config

private struct Config {
    let searchPath: String
    let strict: Bool
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

// MARK: - Patterns to detect

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

        // Time placeholder format
        #"Text\(\s*"--:--"\s*\)"#
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
    "DebugView.swift"
]

// MARK: - Main

private func parseArgs() -> Config {
    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()
    let defaultPath = scriptsDir
        .appendingPathComponent("../TidexApp")
        .standardizedFileURL
        .path

    var searchPath = defaultPath
    var strict = false

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--path", "-p":
            if let value = iterator.next() { searchPath = value }
        case "--strict", "-s":
            strict = true
        case "--help", "-h":
            printHelp()
            exit(0)
        default:
            continue
        }
    }

    return Config(searchPath: searchPath, strict: strict)
}

private func printHelp() {
    print("""
    lint-hardcoded-strings - Find hardcoded strings in SwiftUI views

    Usage: swift run lint-hardcoded-strings [options]

    Options:
      --path, -p <path>    Directory to scan (default: TidexApp)
      --strict, -s         Exit with error code if violations found
      --help, -h           Show this help

    This script scans Swift files for common patterns that suggest
    hardcoded user-visible strings instead of localized ones.

    Detected patterns:
      - Text("literal string")
      - Label("literal string", ...)
      - Button("literal string") { ... }
      - .navigationTitle("literal string")
      - Section("literal string") { ... }
      - TextField("placeholder", ...)
      - .alert("title", ...)

    Allowed patterns (not flagged):
      - Text(.symbolName) - localized symbol
      - String(localized: .key) - proper localization
      - Image(systemName: "...") - SF Symbols
      - Single-word identifiers without spaces
      - Strings in Preview code
    """)
}

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

private func scanFile(_ path: String) -> [Violation] {
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

private func run() {
    let config = parseArgs()

    print("Scanning for hardcoded strings in: \(config.searchPath)")
    print("")

    let swiftFiles = findSwiftFiles(in: config.searchPath)
    var allViolations: [Violation] = []

    for file in swiftFiles {
        let violations = scanFile(file)
        allViolations.append(contentsOf: violations)
    }

    if allViolations.isEmpty {
        print("✓ No hardcoded strings found!")
        return
    }

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

    if config.strict {
        exit(1)
    }
}

run()
