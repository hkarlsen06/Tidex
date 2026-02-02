import Foundation
import SwiftParser
import SwiftSyntax

private struct Catalog: Codable {
    var sourceLanguage: String
    var strings: [String: CatalogEntry]
    var version: String
}

private struct CatalogEntry: Codable {
    var localizations: [String: CatalogLocalization]
}

private struct CatalogLocalization: Codable {
    var stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Codable {
    var state: String
    var value: String
}

private struct Config {
    let inputURL: URL
    let outputURL: URL
    let reportURL: URL?
}

private struct PlaceholderSpec {
    let placeholder: String
    let specifier: String
}

private let placeholderMappings: [String: [PlaceholderSpec]] = [
    "addShift.addShifts": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "addShift.datesSelected": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "addShift.conflictPlural": [PlaceholderSpec(placeholder: "{n}", specifier: "%lld")],
    "addShift.everyNWeeks": [PlaceholderSpec(placeholder: "{n}", specifier: "%lld")],
    "addShift.monthPlural": [PlaceholderSpec(placeholder: "{n}", specifier: "%lld")],
    "addShift.yearPlural": [PlaceholderSpec(placeholder: "{n}", specifier: "%lld")],
    "appearance.info.systemActive": [PlaceholderSpec(placeholder: "{mode}", specifier: "%@")],
    "feedback.charCount": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "monthLimit.confirmDeleteButton": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "monthLimit.confirmDeleteButtonPlural": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "monthLimit.confirmDeleteMessage": [PlaceholderSpec(placeholder: "{months}", specifier: "%@")],
    "monthLimit.deleteExplanation": [
        PlaceholderSpec(placeholder: "{targetMonth}", specifier: "%@"),
        PlaceholderSpec(placeholder: "{otherMonths}", specifier: "%@")
    ],
    "onboarding.settings.payday.customValue": [PlaceholderSpec(placeholder: "{day}", specifier: "%lld")],
    "preview.conflictBadge": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "preview.conflictWarningPlural": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "preview.moreShifts": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "preview.shiftsCount": [PlaceholderSpec(placeholder: "{count}", specifier: "%lld")],
    "security.mfa.addedOn": [PlaceholderSpec(placeholder: "{date}", specifier: "%@")],
    "stats.charts.employment.info": [PlaceholderSpec(placeholder: "{hours}", specifier: "%@")],
    "stats.charts.weeklyChart.bestWeek": [PlaceholderSpec(placeholder: "{week}", specifier: "%lld")],
    "stats.charts.yearlyIncome.title": [PlaceholderSpec(placeholder: "{year}", specifier: "%lld")],
    "stats.monthlyGoal.overTarget": [PlaceholderSpec(placeholder: "{amount}", specifier: "%@")],
    "stats.monthlyGoal.remaining": [PlaceholderSpec(placeholder: "{amount}", specifier: "%@")]
]

private enum ConversionError: Error, CustomStringConvertible {
    case missingDictionary(String)
    case invalidDictionary(String)

    var description: String {
        switch self {
        case .missingDictionary(let name):
            return "Missing dictionary: \(name)"
        case .invalidDictionary(let name):
            return "Invalid dictionary: \(name)"
        }
    }
}

private final class StringDictionaryCollector: SyntaxVisitor {
    private(set) var dictionaries: [String: [String: String]] = [:]

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = pattern.identifier.text
            guard name == "englishStrings" || name == "norwegianStrings" else { continue }
            guard let initializer = binding.initializer?.value else { continue }
            if let dictionary = parseDictionary(from: initializer) {
                dictionaries[name] = dictionary
            }
        }
        return .skipChildren
    }
}

private func parseDictionary(from expr: ExprSyntax) -> [String: String]? {
    guard let dictionary = expr.as(DictionaryExprSyntax.self) else { return nil }

    let elements: DictionaryElementListSyntax
    switch dictionary.content {
    case .elements(let list):
        elements = list
    default:
        return nil
    }

    var result: [String: String] = [:]
    result.reserveCapacity(elements.count)

    for element in elements {
        guard let key = parseStringLiteral(element.key),
              let value = parseStringLiteral(element.value)
        else { continue }
        result[key] = value
    }

    return result
}

private func parseStringLiteral(_ expr: ExprSyntax) -> String? {
    guard let literal = expr.as(StringLiteralExprSyntax.self) else { return nil }
    if let represented = literal.representedLiteralValue {
        return represented
    }

    let description = literal.description.trimmingCharacters(in: .whitespacesAndNewlines)
    return unescapeSwiftStringLiteral(description)
}

private func unescapeSwiftStringLiteral(_ literal: String) -> String? {
    guard let firstQuoteIndex = literal.firstIndex(of: "\"") else { return nil }
    let prefix = literal[..<firstQuoteIndex]
    let hashCount = prefix.filter { $0 == "#" }.count

    let quoteSequence = String(repeating: "#", count: hashCount) + "\""
    let tripleQuoteSequence = quoteSequence + quoteSequence + quoteSequence

    if literal.hasPrefix(tripleQuoteSequence), literal.hasSuffix(tripleQuoteSequence) {
        var trimmed = literal
        trimmed.removeFirst(tripleQuoteSequence.count)
        trimmed.removeLast(tripleQuoteSequence.count)
        return trimmed
    }

    guard literal.hasPrefix(quoteSequence), literal.hasSuffix(quoteSequence) else { return nil }
    var trimmed = literal
    trimmed.removeFirst(quoteSequence.count)
    trimmed.removeLast(quoteSequence.count)

    if hashCount > 0 {
        return trimmed
    }

    return unescapeSwiftString(trimmed)
}

private func unescapeSwiftString(_ text: String) -> String {
    var output = ""
    var index = text.startIndex

    func advance(_ i: inout String.Index) {
        i = text.index(after: i)
    }

    while index < text.endIndex {
        let char = text[index]
        if char != "\\" {
            output.append(char)
            advance(&index)
            continue
        }

        advance(&index)
        if index == text.endIndex {
            output.append("\\")
            break
        }

        let escapeChar = text[index]
        switch escapeChar {
        case "n": output.append("\n")
        case "t": output.append("\t")
        case "r": output.append("\r")
        case "0": output.append("\0")
        case "\\": output.append("\\")
        case "\"": output.append("\"")
        case "u":
            let start = text.index(after: index)
            if start < text.endIndex, text[start] == "{" {
                var scalarIndex = text.index(after: start)
                var hex = ""
                while scalarIndex < text.endIndex, text[scalarIndex] != "}" {
                    hex.append(text[scalarIndex])
                    scalarIndex = text.index(after: scalarIndex)
                }
                if scalarIndex < text.endIndex {
                    if let scalarValue = UInt32(hex, radix: 16),
                       let scalar = UnicodeScalar(scalarValue) {
                        output.append(Character(scalar))
                    }
                    index = scalarIndex
                } else {
                    output.append("u")
                }
            } else {
                output.append("u")
            }
        default:
            output.append(escapeChar)
        }

        advance(&index)
    }

    return output
}

private func applyPlaceholders(_ value: String, replacements: [PlaceholderSpec]?) -> String {
    guard let replacements, !replacements.isEmpty else { return value }
    return replacements.reduce(value) { partial, replacement in
        partial.replacingOccurrences(of: replacement.placeholder, with: replacement.specifier)
    }
}

private func parseConfig() -> Config {
    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()

    let defaultInput = scriptsDir
        .appendingPathComponent("../../backups/Localization/AuthStrings.swift")
        .standardizedFileURL
    let defaultOutput = scriptsDir
        .appendingPathComponent("../TidexApp/Localizable.xcstrings")
        .standardizedFileURL

    var inputURL = defaultInput
    var outputURL = defaultOutput
    var reportURL: URL?

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--input":
            if let value = iterator.next() { inputURL = URL(fileURLWithPath: value) }
        case "--output":
            if let value = iterator.next() { outputURL = URL(fileURLWithPath: value) }
        case "--report":
            if let value = iterator.next() { reportURL = URL(fileURLWithPath: value) }
        default:
            continue
        }
    }

    return Config(inputURL: inputURL, outputURL: outputURL, reportURL: reportURL)
}

private func writeReport(_ lines: [String], to url: URL?) throws {
    guard let url else { return }
    let content = lines.joined(separator: "\n") + "\n"
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func run() throws {
    let config = parseConfig()

    let source = try String(contentsOf: config.inputURL, encoding: .utf8)
    let tree = Parser.parse(source: source)

    let collector = StringDictionaryCollector(viewMode: .sourceAccurate)
    collector.walk(tree)

    guard let english = collector.dictionaries["englishStrings"] else {
        throw ConversionError.missingDictionary("englishStrings")
    }
    guard let norwegian = collector.dictionaries["norwegianStrings"] else {
        throw ConversionError.missingDictionary("norwegianStrings")
    }

    let allKeys = Set(english.keys).union(norwegian.keys)
    var missingInEnglish: [String] = []
    var missingInNorwegian: [String] = []
    var placeholderKeys: [String] = []

    var catalogStrings: [String: CatalogEntry] = [:]
    catalogStrings.reserveCapacity(allKeys.count)

    for key in allKeys.sorted() {
        let englishValue = english[key]
        let norwegianValue = norwegian[key]

        if englishValue == nil { missingInEnglish.append(key) }
        if norwegianValue == nil { missingInNorwegian.append(key) }

        if let value = englishValue, value.contains("{") && value.contains("}"), placeholderMappings[key] == nil {
            placeholderKeys.append(key)
        }

        let replacements = placeholderMappings[key]
        let catalogKey: String
        if let replacements {
            let specifiers = replacements.map { $0.specifier }.joined(separator: " ")
            catalogKey = "\(key) \(specifiers)"
        } else {
            catalogKey = key
        }

        var localizations: [String: CatalogLocalization] = [:]
        if let value = englishValue {
            localizations["en"] = CatalogLocalization(stringUnit: CatalogStringUnit(state: "translated", value: applyPlaceholders(value, replacements: replacements)))
        }
        if let value = norwegianValue {
            localizations["nb"] = CatalogLocalization(stringUnit: CatalogStringUnit(state: "translated", value: applyPlaceholders(value, replacements: replacements)))
        }

        catalogStrings[catalogKey] = CatalogEntry(localizations: localizations)
    }

    let catalog = Catalog(sourceLanguage: "en", strings: catalogStrings, version: "1.0")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(catalog)
    try data.write(to: config.outputURL, options: .atomic)

    var reportLines: [String] = []
    reportLines.append("Converted keys: \(allKeys.count)")
    reportLines.append("Missing English values: \(missingInEnglish.count)")
    reportLines.append("Missing Norwegian values: \(missingInNorwegian.count)")
    reportLines.append("Keys with placeholder tokens: \(placeholderKeys.count)")

    if !missingInEnglish.isEmpty {
        reportLines.append("")
        reportLines.append("Missing English keys:")
        reportLines.append(contentsOf: missingInEnglish)
    }

    if !missingInNorwegian.isEmpty {
        reportLines.append("")
        reportLines.append("Missing Norwegian keys:")
        reportLines.append(contentsOf: missingInNorwegian)
    }

    if !placeholderKeys.isEmpty {
        reportLines.append("")
        reportLines.append("Keys with placeholder tokens (manual review):")
        reportLines.append(contentsOf: placeholderKeys)
    }

    try writeReport(reportLines, to: config.reportURL)

    print("Wrote catalog to \(config.outputURL.path)")
    if let reportURL = config.reportURL {
        print("Wrote report to \(reportURL.path)")
    }
}

try run()
