import Foundation

struct TariffCategory: Codable, Equatable {
  let level: Int
  let labelEn: String
  let labelNb: String

  var label: String { Locale.appLocale.isNorwegian ? labelNb : labelEn }

  private enum CodingKeys: String, CodingKey {
    case level
    case labelEn = "label_en"
    case labelNb = "label_nb"
  }
}

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
  var displayNameEnglish: String?
  var displayNameNorwegian: String?
  var presentation: TariffPresentation?

  var displayName: String {
    Locale.appLocale.isNorwegian
      ? displayNameNorwegian ?? display_name : displayNameEnglish ?? display_name
  }

  private enum CodingKeys: String, CodingKey {
    case id, description, country, presentation
    case display_name, is_default  // swiftlint:disable:this identifier_name
    case displayNameEnglish = "display_name_en"
    case displayNameNorwegian = "display_name_nb"
  }
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
  /// Overtime rules for this tariff version
  let overtime: OvertimeConfig?
  var categories: [TariffCategory]?
  var sourceURLString: String?
  var verifiedOn: String?
  var coverageNoteFallback: String?
  var coverageNoteEnglish: String?
  var coverageNoteNorwegian: String?
  var validThrough: String?
  var legalEffectiveDate: String?

  var coverageNote: String? {
    Locale.appLocale.isNorwegian
      ? coverageNoteNorwegian ?? coverageNoteFallback : coverageNoteEnglish ?? coverageNoteFallback
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, rates, supplements, overtime, categories
    case tariff_type_id, effective_date  // swiftlint:disable:this identifier_name
    case sourceURLString = "source_url"
    case verifiedOn = "verified_on"
    case coverageNoteFallback = "coverage_note"
    case coverageNoteEnglish = "coverage_note_en"
    case coverageNoteNorwegian = "coverage_note_nb"
    case validThrough = "valid_through"
    case legalEffectiveDate = "legal_effective_date"
  }

  func isApplicable(on date: String) -> Bool {
    effective_date <= date && (validThrough.map { date <= $0 } ?? true)
  }

  var sourceURL: URL? {
    guard let sourceURLString, let url = URL(string: sourceURLString), url.scheme == "https" else {
      return nil
    }
    return url
  }

  /// Get hourly wage for a specific level
  /// - Parameter level: The category ID within this agreement.
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

  var effectiveOvertime: OvertimeConfig {
    overtime ?? PayrollCalculator.presetOvertimeConfig
  }
}
