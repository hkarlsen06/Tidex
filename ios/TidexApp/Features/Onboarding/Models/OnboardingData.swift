import Foundation
import Observation

/// Observable data model collecting all onboarding inputs
/// Used to gather wage, supplement, break, tax, and payroll settings during onboarding
@Observable
final class OnboardingData {
  static let defaultJobColor = "#3B82F6"

  // MARK: - Job Settings

  /// Name for the first job created during onboarding.
  var jobName: String = ""

  /// Color used to identify the first job in job pickers.
  var jobColor: String? = defaultJobColor

  // MARK: - Wage Settings

  /// Type of wage: tariff (preset rates) or custom (user-defined)
  var wageType: WageType = .custom

  /// Category ID within the selected agreement.
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

  /// Users paid in a currency other than krone are most likely outside Norway, where tariffs,
  /// the 5.5-hour break rule and Norwegian tax presets don't apply. They skip the supplements
  /// and settings steps and can change those settings later in the app.
  var usesSimpleSetup: Bool {
    currency != "kr"
  }

  /// Defaults for the settings the simple setup skips: pay is hours times the hourly wage.
  func applySimpleSetupDefaults() {
    breakEnabled = false
    taxEnabled = false
  }

  /// User-facing job name, falling back only when older drafts did not collect one.
  func resolvedJobName(locale: Locale? = nil) -> String {
    let trimmedName = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      return OnboardingSaveManager.defaultJobName(locale: locale)
    }
    return trimmedName
  }

  /// Resolved hourly wage based on wage type
  /// Returns tariff rate for tariff users, custom rate for custom users
  /// A tariff must match the selected agreement and contain the selected category.
  var resolvedHourlyWage: Double {
    switch wageType {
    case .tariff:
      if let version = currentTariffVersion, version.tariff_type_id == selectedTariffTypeId,
        let rate = version.rate(forLevel: selectedTariffLevel)
      {
        return rate
      }
      return 0

    case .custom:
      return customHourlyWage
    }
  }

  var hasValidWageSelection: Bool {
    switch wageType {
    case .custom:
      return customHourlyWage.isFinite && customHourlyWage > 0
    case .tariff:
      return currentTariffVersion?.tariff_type_id == selectedTariffTypeId
        && resolvedHourlyWage.isFinite && resolvedHourlyWage > 0
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
      return SupplementRulesSnapshot(rules: [])

    case .custom:
      let rules = supplementRules.map { $0.toSupplementRule() }
      return SupplementRulesSnapshot(rules: rules)
    }
  }

  var resolvedOvertime: OvertimeConfig {
    switch wageType {
    case .tariff:
      return currentTariffVersion?.effectiveOvertime ?? .disabled

    case .custom:
      return .disabled
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
      jobName: jobName,
      jobColor: jobColor,
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
      let persisted = try? JSONDecoder().decode(PersistedOnboardingData.self, from: data)
    else {
      return nil
    }

    self.wageType = persisted.wageType
    self.jobName = persisted.jobName ?? ""
    self.jobColor = persisted.jobColor ?? Self.defaultJobColor
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
  let jobName: String?
  let jobColor: String?
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
  var sourceRule: SupplementRule?

  init(from rule: OnboardingSupplementRule) {
    self.id = rule.id
    self.days = Array(rule.days)
    self.fromTime = rule.fromTime
    self.toTime = rule.toTime
    self.type = rule.type.rawValue
    self.value = rule.value
    self.sourceRule = rule.sourceRule
  }

  func toOnboardingSupplementRule() -> OnboardingSupplementRule {
    OnboardingSupplementRule(
      id: id,
      days: Set(days),
      fromTime: fromTime,
      toTime: toTime,
      type: OnboardingSupplementRule.SupplementType(rawValue: type) ?? .fixed,
      value: value,
      sourceRule: sourceRule
    )
  }
}

// MARK: - Onboarding Supplement Rule

/// Supplement rule for onboarding (simplified for UI)
struct OnboardingSupplementRule: Identifiable, Equatable {
  let id: UUID
  var days: Set<Int>  // 1-7 where 1=Monday, 7=Sunday
  var fromTime: String  // HH:mm format
  var toTime: String  // HH:mm format
  var type: SupplementType
  var value: Double  // Either fixed kr/t or percentage
  var sourceRule: SupplementRule?

  init(
    id: UUID = UUID(),
    days: Set<Int> = [],
    fromTime: String = "18:00",
    toTime: String = "21:00",
    type: SupplementType = .fixed,
    value: Double = 22,
    sourceRule: SupplementRule? = nil
  ) {
    self.id = id
    self.days = days
    self.fromTime = fromTime
    self.toTime = toTime
    self.type = type
    self.value = value
    self.sourceRule = sourceRule
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
      percent: type == .percent ? value : nil,
      stackingGroup: sourceRule?.stackingGroup,
      dates: sourceRule?.dates,
      excludedDates: sourceRule?.excludedDates,
      shiftStartDates: sourceRule?.shiftStartDates,
      excludedShiftStartDates: sourceRule?.excludedShiftStartDates,
      shiftStartBefore: sourceRule?.shiftStartBefore,
      minimumRate: sourceRule?.minimumRate,
      percentageBaseRate: sourceRule?.percentageBaseRate
    )
  }

  /// Human-readable summary of days
  var daysDescription: String {
    describeDays { OnboardingWeekday.initial(for: $0) }
  }

  /// Same as `daysDescription`, but with full weekday names for VoiceOver.
  var spokenDaysDescription: String {
    describeDays { OnboardingWeekday.name(for: $0) }
  }

  private func describeDays(dayLabel: (Int) -> String) -> String {
    if days.isEmpty { return "" }

    let sortedDays = Array(days).sorted()

    // Check for consecutive ranges
    if sortedDays == [1, 2, 3, 4, 5] {
      return String(localized: .onboardingSupplementsWeekdaysLong)
    }
    if sortedDays == [6, 7] {  // swiftlint:disable:this no_magic_numbers
      return String(localized: .onboardingSupplementsWeekendLong)
    }
    if sortedDays == Array(1...7) {  // swiftlint:disable:this no_magic_numbers
      return String(localized: .onboardingSupplementsAllDaysLong)
    }

    return sortedDays.map(dayLabel).joined(separator: ", ")
  }

  /// Human-readable time range
  var timeDescription: String {
    "\(fromTime) - \(toTime)"
  }

  /// Human-readable value with localization and currency
  func valueDescription(locale: Locale, currency: String = "kr") -> String {  // swiftlint:disable:this explicit_acl
    let formatted = value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    switch type {
    case .fixed:
      let currencyConfig = CurrencyConfig.get(currency)
      let hourPart = String(localized: .commonPerHourShort)
      let amount =
        currencyConfig.display == .prefix
        ? "\(currencyConfig.value)\(formatted)" : "\(formatted) \(currencyConfig.value)"
      return "+\(amount)\(hourPart)"

    case .percent:
      return "+\(formatted)%"
    }
  }
}

// MARK: - Tariff Level

/// Tariff level with display information
struct TariffLevel: Identifiable {
  let level: Int
  let rate: Double
  var label: String?
  var displayName: String { label ?? Self.displayName(forLevel: level) }

  var id: Int { level }

  /// Format rate for display (e.g., "184,54 kr/t").
  /// These tariff levels are Norwegian collective-agreement rates denominated in NOK regardless
  /// of the user's chosen display currency, so the "kr" stays fixed; the per-hour suffix, digit
  /// grouping and decimal separator follow the app's locale.
  var formattedRate: String {
    let formatted = rate.formatted(
      .number.precision(.fractionLength(2)).locale(.appLocale)
    )
    return "\(formatted) kr\(String(localized: .commonPerHourShort))"
  }

  static func displayName(forLevel level: Int) -> String {  // swiftlint:disable:this explicit_acl
    String(localized: .onboardingWageLevel(level))
  }

  /// Build tariff levels dynamically from a TariffVersion
  /// - Parameter tariffVersion: The tariff version containing rates
  /// - Returns: Array of TariffLevel built from version rates
  static func from(tariffVersion: TariffVersion) -> [Self] {  // swiftlint:disable:this explicit_acl
    let categories = tariffVersion.categories ?? []
    let order = categories.map(\.level)
    let remaining = tariffVersion.availableLevels.filter { !order.contains($0) }
    return (order + remaining).compactMap { level in
      guard let rate = tariffVersion.rate(forLevel: level) else { return nil }
      let label = categories.first { $0.level == level }?.label
      return Self(level: level, rate: rate, label: label)
    }
  }
}

/// Weekday labels that follow the app language. Days are numbered 1 (Monday) to 7 (Sunday).
enum OnboardingWeekday {
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .appLocale
    return calendar
  }

  /// Symbol arrays start on Sunday, so Sunday (7) maps to index 0.
  private static func symbolIndex(for day: Int) -> Int {
    day % 7  // swiftlint:disable:this no_magic_numbers
  }

  static func initial(for day: Int) -> String {
    calendar.veryShortStandaloneWeekdaySymbols[symbolIndex(for: day)]
  }

  static func name(for day: Int) -> String {
    calendar.standaloneWeekdaySymbols[symbolIndex(for: day)]
  }
}
