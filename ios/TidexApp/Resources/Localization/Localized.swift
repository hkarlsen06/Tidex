import Foundation

extension Locale {
  /// App locale derived from the app's preferred localization (falls back to system locale)
  static var appLocale: Locale {
    let identifier =
      Bundle.main.preferredLocalizations.first
      ?? Locale.autoupdatingCurrent.identifier
    return Locale(identifier: identifier)
  }

  /// Whether the current locale is Norwegian (nb, nn, or no)
  var isNorwegian: Bool {
    let code = language.languageCode?.identifier ?? ""
    return code == "nb" || code == "nn" || code == "no"
  }

  /// Language code for URLs (e.g., "en", "no", "de")
  /// Maps Norwegian variants to "no" for URL consistency
  var urlLanguageCode: String {
    let code = language.languageCode?.identifier ?? "en"
    switch code {
    case "nb", "nn", "no":
      return "no"
    default:
      return code
    }
  }
}
