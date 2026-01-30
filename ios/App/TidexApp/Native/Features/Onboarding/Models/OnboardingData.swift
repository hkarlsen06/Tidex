import Foundation
import SwiftUI

/// Observable data model collecting all onboarding inputs
/// Used to gather wage, supplement, break, tax, and payroll settings during onboarding
@Observable
final class OnboardingData {
    // MARK: - Profile Settings

    /// User's display name (for users who don't have one, e.g., Apple Sign-In)
    var displayName: String = ""

    /// Whether the user had a name when onboarding started (determines if profile screen shows)
    var initiallyHadName: Bool = false

    // MARK: - Wage Settings

    /// Type of wage: tariff (preset rates) or custom (user-defined)
    var wageType: WageType = .custom

    /// Selected tariff level (1-6 for standard, -1/-2 for under 18)
    var selectedTariffLevel: Int = 1

    /// Custom hourly wage when using custom wage type
    var customHourlyWage: Double = 200.0

    /// Whether wage has been initialized based on locale
    var hasInitializedWageForLocale: Bool = false

    // MARK: - Tariff Type Settings

    /// Selected tariff type ID (e.g., "hk_retail")
    var selectedTariffTypeId: String = "hk_retail"

    /// Available tariff types loaded from server
    var availableTariffTypes: [TariffType] = []

    /// Current tariff version for the selected tariff type
    var currentTariffVersion: TariffVersion?

    // MARK: - Supplement Settings

    /// Custom supplement rules (only used for custom wage type)
    var supplementRules: [OnboardingSupplementRule] = []

    // MARK: - Break Settings

    /// Whether break deduction is enabled
    var breakEnabled: Bool = true

    // MARK: - Tax Settings

    /// Whether to show tax deductions
    var taxEnabled: Bool = false

    /// Tax percentage (when tax is enabled)
    var taxPercentage: Double = 22

    // MARK: - Payroll Settings

    /// Day of month when pay is received (1-28)
    var payrollDay: Int = 15

    // MARK: - Display Settings

    /// Selected currency symbol (stored in DB)
    var currency: String = "kr"

    // MARK: - Computed Properties

    /// Resolved hourly wage based on wage type
    /// Returns tariff rate for tariff users, custom rate for custom users
    /// Uses tariff version rates when available, falls back to hardcoded rates
    var resolvedHourlyWage: Double {
        switch wageType {
        case .tariff:
            // Use version-specific rate if available, otherwise fallback to static rates
            if let version = currentTariffVersion,
               let rate = version.rate(forLevel: selectedTariffLevel) {
                return rate
            }
            return PayrollCalculator.presetWageRates[String(selectedTariffLevel)] ?? 184.54
        case .custom:
            return customHourlyWage
        }
    }

    /// Resolved tariff type ID (nil for custom wage users)
    var resolvedTariffTypeId: String? {
        switch wageType {
        case .tariff:
            return selectedTariffTypeId
        case .custom:
            return nil
        }
    }

    /// Resolved wage level (nil for custom wage users)
    var resolvedWageLevel: Int? {
        switch wageType {
        case .tariff:
            return selectedTariffLevel
        case .custom:
            return nil
        }
    }

    /// Resolved supplement rules
    /// Returns preset rules for tariff users, custom rules for custom users
    /// Uses tariff version supplements when available, falls back to hardcoded rules
    var resolvedSupplements: SupplementRulesSnapshot {
        switch wageType {
        case .tariff:
            // Use version-specific supplements if available
            if let version = currentTariffVersion {
                return version.supplements
            }
            return SupplementRulesSnapshot(rules: PayrollCalculator.presetSupplementRules)
        case .custom:
            let rules = supplementRules.map { $0.toSupplementRule() }
            return SupplementRulesSnapshot(rules: rules)
        }
    }

    // MARK: - Types

    /// Type of wage configuration
    enum WageType: String, Codable {
        case tariff
        case custom
    }

    // MARK: - Persistence

    private static let storageKey = "onboarding_data_draft"
    private static let screenKey = "onboarding_current_screen"

    /// Save current state to UserDefaults for persistence across app restarts
    func save(currentScreen: String) {
        let persistedData = PersistedOnboardingData(
            displayName: displayName,
            initiallyHadName: initiallyHadName,
            wageType: wageType,
            selectedTariffLevel: selectedTariffLevel,
            customHourlyWage: customHourlyWage,
            hasInitializedWageForLocale: hasInitializedWageForLocale,
            selectedTariffTypeId: selectedTariffTypeId,
            supplementRules: supplementRules.map { PersistedSupplementRule(from: $0) },
            breakEnabled: breakEnabled,
            taxEnabled: taxEnabled,
            taxPercentage: taxPercentage,
            payrollDay: payrollDay,
            currency: currency
        )

        if let encoded = try? JSONEncoder().encode(persistedData) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
            UserDefaults.standard.set(currentScreen, forKey: Self.screenKey)
        }
    }

    /// Restore state from UserDefaults
    /// Returns the saved screen name if data was restored, nil otherwise
    @discardableResult
    func restore() -> String? {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let persisted = try? JSONDecoder().decode(PersistedOnboardingData.self, from: data) else {
            return nil
        }

        self.displayName = persisted.displayName ?? ""
        self.initiallyHadName = persisted.initiallyHadName ?? false
        self.wageType = persisted.wageType
        self.selectedTariffLevel = persisted.selectedTariffLevel
        self.customHourlyWage = persisted.customHourlyWage
        self.hasInitializedWageForLocale = persisted.hasInitializedWageForLocale
        self.selectedTariffTypeId = persisted.selectedTariffTypeId ?? "hk_retail"
        self.supplementRules = persisted.supplementRules.map { $0.toOnboardingSupplementRule() }
        self.breakEnabled = persisted.breakEnabled
        self.taxEnabled = persisted.taxEnabled
        self.taxPercentage = persisted.taxPercentage
        self.payrollDay = persisted.payrollDay
        self.currency = persisted.currency ?? "kr"

        return UserDefaults.standard.string(forKey: Self.screenKey)
    }

    /// Clear saved onboarding data (call after successful completion)
    static func clearSavedData() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: screenKey)
    }

    /// Check if there's saved onboarding data
    static var hasSavedData: Bool {
        UserDefaults.standard.data(forKey: storageKey) != nil
    }
}

// MARK: - Persisted Data Models (Codable)

/// Codable wrapper for OnboardingData persistence
private struct PersistedOnboardingData: Codable {
    let displayName: String?
    let initiallyHadName: Bool?
    let wageType: OnboardingData.WageType
    let selectedTariffLevel: Int
    let customHourlyWage: Double
    let hasInitializedWageForLocale: Bool
    let selectedTariffTypeId: String?
    let supplementRules: [PersistedSupplementRule]
    let breakEnabled: Bool
    let taxEnabled: Bool
    let taxPercentage: Double
    let payrollDay: Int
    let currency: String?
}

/// Codable wrapper for OnboardingSupplementRule persistence
private struct PersistedSupplementRule: Codable {
    let id: UUID
    let days: [Int]
    let fromTime: String
    let toTime: String
    let type: String
    let value: Double

    init(from rule: OnboardingSupplementRule) {
        self.id = rule.id
        self.days = Array(rule.days)
        self.fromTime = rule.fromTime
        self.toTime = rule.toTime
        self.type = rule.type.rawValue
        self.value = rule.value
    }

    func toOnboardingSupplementRule() -> OnboardingSupplementRule {
        OnboardingSupplementRule(
            id: id,
            days: Set(days),
            fromTime: fromTime,
            toTime: toTime,
            type: OnboardingSupplementRule.SupplementType(rawValue: type) ?? .fixed,
            value: value
        )
    }
}

// MARK: - Onboarding Supplement Rule

/// Supplement rule for onboarding (simplified for UI)
struct OnboardingSupplementRule: Identifiable, Equatable {
    let id: UUID
    var days: Set<Int> // 1-7 where 1=Monday, 7=Sunday
    var fromTime: String // HH:mm format
    var toTime: String // HH:mm format
    var type: SupplementType
    var value: Double // Either fixed kr/t or percentage

    init(
        id: UUID = UUID(),
        days: Set<Int> = [],
        fromTime: String = "18:00",
        toTime: String = "21:00",
        type: SupplementType = .fixed,
        value: Double = 22
    ) {
        self.id = id
        self.days = days
        self.fromTime = fromTime
        self.toTime = toTime
        self.type = type
        self.value = value
    }

    enum SupplementType: String, CaseIterable {
        case fixed
        case percent
    }

    /// Convert to SupplementRule for saving
    func toSupplementRule() -> SupplementRule {
        SupplementRule(
            days: Array(days).sorted(),
            from: fromTime,
            to: toTime,
            rate: type == .fixed ? value : nil,
            percent: type == .percent ? value : nil
        )
    }

    /// Human-readable summary of days with localization
    func daysDescription(locale: LocalizationManager.AppLocale) -> String {
        if days.isEmpty { return "" }

        let dayNames = ["M", "T", "O", "T", "F", "L", "S"]
        let sortedDays = Array(days).sorted()

        // Check for consecutive ranges
        if sortedDays == [1, 2, 3, 4, 5] {
            return AuthStrings.string("onboarding.supplements.weekdaysLong", locale: locale)
        } else if sortedDays == [6, 7] {
            return AuthStrings.string("onboarding.supplements.weekendLong", locale: locale)
        } else if sortedDays == Array(1...7) {
            return AuthStrings.string("onboarding.supplements.allDaysLong", locale: locale)
        }

        return sortedDays.map { dayNames[$0 - 1] }.joined(separator: ", ")
    }

    /// Human-readable time range
    var timeDescription: String {
        "\(fromTime) - \(toTime)"
    }

    /// Human-readable value with localization and currency
    func valueDescription(locale: LocalizationManager.AppLocale, currency: String = "kr") -> String {
        switch type {
        case .fixed:
            let currencyConfig = CurrencyConfig.get(currency)
            let hourPart = locale == .norwegian ? "/t" : "/hr"
            let suffix = currencyConfig.display == .prefix
                ? "\(currencyConfig.value)\(hourPart)"
                : "\(currencyConfig.value)\(hourPart)"
            return "+\(Int(value)) \(suffix)"
        case .percent:
            return "+\(Int(value))%"
        }
    }
}

// MARK: - Tariff Level

/// Tariff level with display information
struct TariffLevel: Identifiable {
    let level: Int
    let rate: Double
    let displayName: String

    var id: Int { level }

    /// Format rate for display (e.g., "184,54 kr/t")
    var formattedRate: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "nb_NO")
        let formatted = formatter.string(from: NSNumber(value: rate)) ?? "\(rate)"
        return "\(formatted) kr/t"
    }

    /// All available tariff levels from PayrollCalculator (fallback for offline)
    static let all: [TariffLevel] = [
        TariffLevel(level: -1, rate: 129.91, displayName: "Under 16"),
        TariffLevel(level: -2, rate: 132.90, displayName: "16 - 18"),
        TariffLevel(level: 1, rate: 184.54, displayName: "Lønnstrinn 1"),
        TariffLevel(level: 2, rate: 185.38, displayName: "Lønnstrinn 2"),
        TariffLevel(level: 3, rate: 187.46, displayName: "Lønnstrinn 3"),
        TariffLevel(level: 4, rate: 193.05, displayName: "Lønnstrinn 4"),
        TariffLevel(level: 5, rate: 210.81, displayName: "Lønnstrinn 5"),
        TariffLevel(level: 6, rate: 256.14, displayName: "Lønnstrinn 6"),
    ]

    /// Standard level display names by level number
    private static let levelDisplayNames: [Int: String] = [
        -1: "Under 16",
        -2: "16 - 18",
        1: "Lønnstrinn 1",
        2: "Lønnstrinn 2",
        3: "Lønnstrinn 3",
        4: "Lønnstrinn 4",
        5: "Lønnstrinn 5",
        6: "Lønnstrinn 6",
    ]

    /// Build tariff levels dynamically from a TariffVersion
    /// - Parameter tariffVersion: The tariff version containing rates
    /// - Returns: Array of TariffLevel built from version rates
    static func from(tariffVersion: TariffVersion) -> [TariffLevel] {
        // Define the expected order of levels
        let levelOrder = [-1, -2, 1, 2, 3, 4, 5, 6]

        return levelOrder.compactMap { level in
            guard let rate = tariffVersion.rate(forLevel: level) else { return nil }
            let displayName = levelDisplayNames[level] ?? "Level \(level)"
            return TariffLevel(level: level, rate: rate, displayName: displayName)
        }
    }
}
