import Foundation

private struct Catalog: Codable {
    var sourceLanguage: String
    var strings: [String: CatalogEntry]
    var version: String
}

private struct CatalogEntry: Codable {
    var localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Codable {
    var stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Codable {
    var value: String
}

private struct Config {
    let catalogURL: URL
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
    "stats.charts.yearlyIncome.title": [PlaceholderSpec(placeholder: "{year}", specifier: "%@")],
    "stats.monthlyGoal.overTarget": [PlaceholderSpec(placeholder: "{amount}", specifier: "%@")],
    "stats.monthlyGoal.remaining": [PlaceholderSpec(placeholder: "{amount}", specifier: "%@")]
]

private enum ValidationError: Error, CustomStringConvertible {
    case missingFile(String)

    var description: String {
        switch self {
        case .missingFile(let name):
            return "Missing file: \(name)"
        }
    }
}

private func parseConfig() -> Config {
    let scriptURL = URL(fileURLWithPath: #filePath)
    let scriptsDir = scriptURL.deletingLastPathComponent()
    let defaultCatalog = scriptsDir
        .appendingPathComponent("../TidexApp/Localizable.xcstrings")
        .standardizedFileURL

    var catalogURL = defaultCatalog

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--catalog":
            if let value = iterator.next() { catalogURL = URL(fileURLWithPath: value) }
        default:
            continue
        }
    }

    return Config(catalogURL: catalogURL)
}

private func findMissingLocalizations(in catalog: Catalog) -> [String] {
    var missing: [String] = []
    for (key, entry) in catalog.strings {
        guard let localizations = entry.localizations, !localizations.isEmpty else { continue }
        let locales = localizations.keys
        if !locales.contains("en") || !locales.contains("nb") {
            missing.append(key)
        }
    }
    return missing
}

private func validatePlaceholders(
    in catalog: Catalog
) -> (missingEntries: [String], missingSpecifiers: [String]) {
    var missingEntries: [String] = []
    var missingSpecifiers: [String] = []

    for (base, replacements) in placeholderMappings {
        guard let entry = catalog.strings[base],
              let localizations = entry.localizations,
              !localizations.isEmpty else {
            missingEntries.append(base)
            continue
        }

        for (locale, localization) in localizations {
            guard let value = localization.stringUnit?.value else {
                missingSpecifiers.append("\(base) [\(locale)] missing value")
                continue
            }
            for replacement in replacements where !value.contains(replacement.specifier) {
                missingSpecifiers.append("\(base) [\(locale)] missing \(replacement.specifier)")
            }
        }
    }
    return (missingEntries, missingSpecifiers)
}

private func printIssues(_ items: [String], header: String) {
    guard !items.isEmpty else { return }
    print("\(header): \(items.count)")
    items.forEach { print("  \($0)") }
}

private func run() throws {
    let config = parseConfig()

    guard FileManager.default.fileExists(atPath: config.catalogURL.path) else {
        throw ValidationError.missingFile(config.catalogURL.path)
    }

    let catalogData = try Data(contentsOf: config.catalogURL)
    let catalog = try JSONDecoder().decode(Catalog.self, from: catalogData)

    let missingLocalizations = findMissingLocalizations(in: catalog)
    let (missingEntries, missingSpecifiers) = validatePlaceholders(in: catalog)

    let hasIssues = !missingLocalizations.isEmpty || !missingEntries.isEmpty || !missingSpecifiers.isEmpty
    guard hasIssues else {
        print("Localization validation passed. Catalog entries: \(catalog.strings.count).")
        return
    }

    printIssues(missingLocalizations, header: "Missing localizations for entries")
    printIssues(missingEntries, header: "Missing placeholder entries")
    printIssues(missingSpecifiers, header: "Missing placeholder specifiers")
    exit(1)
}

try run()
