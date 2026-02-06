import Foundation

// MARK: - Tariff Type

/// A tariff type representing a specific collective agreement (e.g., "HK Detaljhandel")
/// These are the available tariff systems that users can select for their wage calculations
struct TariffType: Codable, Identifiable, Equatable {
  /// Unique identifier (e.g., "hk_retail")
  let id: String
  /// Human-readable name (e.g., "HK Detaljhandel")
  let display_name: String
  /// Optional description of the tariff
  let description: String?
  /// Country code (e.g., "NO")
  let country: String
  /// Whether this is the default tariff type for new users
  let is_default: Bool
}

// MARK: - Tariff Version

/// A specific version of a tariff with effective date and rate information
/// Tariff versions contain the actual wage rates and supplement rules for a point in time
struct TariffVersion: Codable, Identifiable, Equatable {
  /// Unique identifier
  let id: String
  /// The tariff type this version belongs to
  let tariff_type_id: String
  /// ISO date (YYYY-MM-DD) when this version becomes effective
  let effective_date: String
  /// Optional human-readable name (e.g., "2025 Tariff")
  let name: String?
  /// Hourly wage rates keyed by level number as string (e.g., "1": 188.50)
  let rates: [String: Double]
  /// Supplement rules for this tariff version
  let supplements: SupplementRulesSnapshot

  /// Get hourly wage for a specific level
  /// - Parameter level: The wage level (1-9)
  /// - Returns: The hourly rate in NOK, or nil if level not found
  func rate(forLevel level: Int) -> Double? {
    rates[String(level)]
  }

  /// Get all available wage levels sorted
  var availableLevels: [Int] {
    rates.keys.compactMap { Int($0) }.sorted()
  }

  /// Get the minimum available wage rate
  var minimumRate: Double? {
    rates.values.min()
  }

  /// Get the maximum available wage rate
  var maximumRate: Double? {
    rates.values.max()
  }
}
