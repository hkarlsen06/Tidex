import Foundation

/// Resolves onboarding currency defaults and wage presets from locale.
enum OnboardingCurrencyResolver {
  /// ISO 4217 currency codes mapped to supported Tidex display symbols.
  private static let currencyCodeToSymbol: [String: String] = [
    "NOK": "kr",
    "SEK": "kr",
    "DKK": "kr",
    "USD": "$",
    "CAD": "C$",
    "AUD": "A$",
    "SGD": "S$",
    "EUR": "€",
    "GBP": "£",
    "JPY": "¥",
    "KRW": "₩",
    "INR": "₹",
    "CZK": "Kč",
    "PLN": "zł",
    "RUB": "₽",
    "BRL": "R$",
    "ZAR": "R",
    "THB": "฿",
  ]

  /// Region fallback for supported symbols when Foundation currency metadata is unavailable.
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
    if let currencyCode = locale.currency?.identifier.uppercased(),
      let currencySymbol = currencyCodeToSymbol[currencyCode],
      isSupportedCurrency(currencySymbol)
    {
      return currencySymbol
    }

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
