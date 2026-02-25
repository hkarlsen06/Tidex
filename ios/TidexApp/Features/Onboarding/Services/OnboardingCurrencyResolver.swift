import Foundation

/// Resolves onboarding currency defaults and wage presets from locale.
enum OnboardingCurrencyResolver {
  /// Region-first map to supported currency symbols.
  private static let regionToCurrency: [String: String] = [
    // Krone
    "NO": "kr",
    "SE": "kr",
    "DK": "kr",

    // Dollar families
    "US": "$",
    "CA": "C$",
    "AU": "A$",
    "SG": "S$",

    // Euro
    "AT": "€",
    "BE": "€",
    "CY": "€",
    "DE": "€",
    "EE": "€",
    "ES": "€",
    "FI": "€",
    "FR": "€",
    "GR": "€",
    "HR": "€",
    "IE": "€",
    "IT": "€",
    "LT": "€",
    "LU": "€",
    "LV": "€",
    "MT": "€",
    "NL": "€",
    "PT": "€",
    "SI": "€",
    "SK": "€",

    // Other explicit mappings
    "GB": "£",
    "JP": "¥",
    "KR": "₩",
    "IN": "₹",
    "CZ": "Kč",
    "PL": "zł",
    "RU": "₽",
    "BR": "R$",
    "ZA": "R",
    "TH": "฿",
  ]

  static func detectDefaultCurrency(locale: Locale = .current) -> String {
    if let regionCode = locale.region?.identifier,
      let regionCurrency = regionToCurrency[regionCode],
      isSupportedCurrency(regionCurrency)
    {
      return regionCurrency
    }

    let languageCode = locale.language.languageCode?.identifier ?? ""

    if ["nb", "nn", "no"].contains(languageCode) {
      return "kr"
    }

    return "$"
  }

  static func defaultHourlyWage(for currency: String) -> Double {
    CurrencyConfig.get(currency).wageRangeTier.defaultValue
  }

  static func isSupportedCurrency(_ symbol: String) -> Bool {
    CurrencyConfig.all.contains(where: { $0.value == symbol })
  }
}
