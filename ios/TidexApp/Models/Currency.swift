import Foundation
import SwiftUI

/// Position of currency symbol relative to amount
enum CurrencyDisplay: String, Codable {
  case prefix  // Symbol before amount (e.g., "$100")
  case suffix  // Symbol after amount (e.g., "100 kr")
}

/// Wage range tier for currencies based on typical hourly wages
/// Currencies are grouped by similar purchasing power/wage levels
enum WageRangeTier: Equatable {
  /// High-value currencies (NOK, SEK, DKK, CZK, etc.) - typical hourly wages 150-550
  case high
  /// Medium-value currencies (USD, EUR, GBP, CAD, AUD, etc.) - typical hourly wages 15-75
  case medium
  /// Low-value currencies (INR, PHP, etc.) - typical hourly wages 100-1000
  case low
  /// Very low-value currencies (JPY, KRW, etc.) - typical hourly wages 1000-5000
  case veryLow

  /// Slider minimum value for this tier
  var minValue: Double {
    switch self {
    case .high:
      return 150  // swiftlint:disable:this no_magic_numbers

    case .medium:
      return 15  // swiftlint:disable:this no_magic_numbers

    case .low:
      return 100

    case .veryLow:
      return 1_000  // swiftlint:disable:this no_magic_numbers
    }
  }

  /// Slider maximum value for this tier
  var maxValue: Double {
    switch self {
    case .high:
      return 550  // swiftlint:disable:this no_magic_numbers

    case .medium:
      return 75  // swiftlint:disable:this no_magic_numbers

    case .low:
      return 1_000  // swiftlint:disable:this no_magic_numbers

    case .veryLow:
      return 5_000  // swiftlint:disable:this no_magic_numbers
    }
  }

  /// Default starting value for this tier
  var defaultValue: Double {
    switch self {
    case .high:
      return 200  // swiftlint:disable:this no_magic_numbers

    case .medium:
      return 25  // swiftlint:disable:this no_magic_numbers

    case .low:
      return 300  // swiftlint:disable:this no_magic_numbers

    case .veryLow:
      return 2_000  // swiftlint:disable:this no_magic_numbers
    }
  }
}

/// Currency option for the currency selector
/// Mirrors the structure from lib/currency/currencies.ts in the Next.js app
struct CurrencyOption: Identifiable, Equatable {
  /// The symbol/text stored in DB and displayed (e.g., "$", "€", "kr")
  let value: String

  /// Label shown in the selector
  let label: String

  /// Whether symbol appears before or after the amount
  let display: CurrencyDisplay

  /// The wage range tier for this currency
  let wageRangeTier: WageRangeTier

  var id: String { value }
}

/// Group of currency options for organized display
struct CurrencyGroup: Identifiable {
  let label: String
  let options: [CurrencyOption]

  var id: String { label }
}

extension CurrencyGroup {
  /// Localized display label for picker section headers.
  var localizedLabel: String {
    switch label {
    case "Krone":
      return String(localized: .commonCurrencyGroupKrone)

    case "Popular":
      return String(localized: .commonCurrencyGroupPopular)

    case "Other":
      return String(localized: .commonCurrencyGroupOther)

    default:
      return label
    }
  }
}

/// Currency configuration matching the Next.js app
enum CurrencyConfig {
  /// All currency groups (Krone first, then Popular, then Other)
  /// Wage range tiers:
  /// - high: NOK, SEK, DKK, CZK, Ruble - hourly wages typically 150-550
  /// - medium: USD, EUR, GBP, CAD, AUD, SGD, CHF - hourly wages typically 15-75
  /// - low: INR, BRL, ZAR, THB, PLN - hourly wages typically 100-1000
  /// - veryLow: JPY, KRW - hourly wages typically 1000-5000
  static let groups: [CurrencyGroup] = [
    CurrencyGroup(
      label: "Krone",
      options: [
        CurrencyOption(value: "kr", label: "kr", display: .suffix, wageRangeTier: .high)
      ]
    ),
    CurrencyGroup(
      label: "Popular",
      options: [
        CurrencyOption(value: "$", label: "Dollar ($)", display: .prefix, wageRangeTier: .medium),
        CurrencyOption(value: "€", label: "Euro (€)", display: .prefix, wageRangeTier: .medium),
        CurrencyOption(value: "£", label: "Pound (£)", display: .prefix, wageRangeTier: .medium),
        CurrencyOption(value: "¥", label: "Yen (¥)", display: .prefix, wageRangeTier: .veryLow),
      ]
    ),
    CurrencyGroup(
      label: "Other",
      options: [
        CurrencyOption(value: "C$", label: "C$", display: .prefix, wageRangeTier: .medium),
        CurrencyOption(value: "A$", label: "A$", display: .prefix, wageRangeTier: .medium),
        CurrencyOption(value: "S$", label: "S$", display: .prefix, wageRangeTier: .medium),
        CurrencyOption(value: "R$", label: "R$", display: .prefix, wageRangeTier: .low),
        CurrencyOption(value: "zł", label: "Zloty (zł)", display: .suffix, wageRangeTier: .low),
        CurrencyOption(value: "Kč", label: "Koruna (Kč)", display: .suffix, wageRangeTier: .high),
        CurrencyOption(value: "₹", label: "Rupee (₹)", display: .prefix, wageRangeTier: .low),
        CurrencyOption(value: "₽", label: "Ruble (₽)", display: .suffix, wageRangeTier: .high),
        CurrencyOption(value: "₩", label: "Won (₩)", display: .prefix, wageRangeTier: .veryLow),
        CurrencyOption(value: "R", label: "Rand (R)", display: .prefix, wageRangeTier: .low),
        CurrencyOption(value: "฿", label: "Baht (฿)", display: .prefix, wageRangeTier: .low),
      ]
    ),
  ]

  /// Flat list of all currencies for lookup
  internal static let all: [CurrencyOption] = groups.flatMap(\.options)

  /// Default currency (Norwegian krone)
  static let defaultCurrency = CurrencyOption(
    value: "kr", label: "kr", display: .suffix, wageRangeTier: .high)

  /// Get currency config by its stored value
  static func get(_ value: String) -> CurrencyOption {
    all.first { $0.value == value } ?? defaultCurrency
  }

  /// Format an amount with the currency symbol
  static func format(_ amount: Double, currency: String, includeDecimals: Bool = false) -> String {
    let config = get(currency)
    let formatter = FormatterCache.numberFormatter(
      includeDecimals: includeDecimals,
      locale: Locale.appLocale
    )
    let formattedNumber = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"

    switch config.display {
    case .prefix:
      return "\(config.value)\(formattedNumber)"

    case .suffix:
      return "\(formattedNumber) \(config.value)"
    }
  }

  /// Format an empty/placeholder amount while preserving currency placement.
  static func formatEmpty(currency: String) -> String {
    let config = get(currency)

    switch config.display {
    case .prefix:
      return "\(config.value)---"

    case .suffix:
      return "--- \(config.value)"
    }
  }

  /// Format an amount without the currency symbol (for breakdown displays)
  static func formatPlain(_ amount: Double, includeDecimals: Bool = false) -> String {
    let formatter = FormatterCache.numberFormatter(
      includeDecimals: includeDecimals,
      locale: Locale.appLocale
    )
    return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
  }
}

// MARK: - Environment Key for User Currency

/// Environment key for the user's selected currency
/// This allows components to access the currency setting from their environment
private struct UserCurrencyKey: EnvironmentKey {
  static let defaultValue: String = "kr"
}

extension EnvironmentValues {
  /// The user's selected currency symbol (e.g., "kr", "$", "€")
  /// Set this at the top of your view hierarchy from user settings
  var userCurrency: String {
    get { self[UserCurrencyKey.self] }
    set { self[UserCurrencyKey.self] = newValue }
  }
}

// MARK: - Currency Formatting Extension

extension View {
  /// Sets the user currency for this view hierarchy
  func userCurrency(_ currency: String) -> some View {
    environment(\.userCurrency, currency)
  }
}
