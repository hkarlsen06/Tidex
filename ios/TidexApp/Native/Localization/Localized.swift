import SwiftUI

/// Supported languages in the Tidex app
enum TidexLanguage: String, CaseIterable {
    case english = "en"
    case norwegian = "no"
    case german = "de"

    /// The locale identifier for date/number formatting (e.g., "nb_NO", "de_DE", "en_US")
    var formatterLocaleIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .norwegian: return "nb_NO"
        case .german: return "de_DE"
        }
    }

    /// The locale for use with DateFormatter, NumberFormatter, etc.
    var formatterLocale: Locale {
        Locale(identifier: formatterLocaleIdentifier)
    }
}

extension Locale {
    /// Returns the detected TidexLanguage based on system locale
    var tidexLanguage: TidexLanguage {
        let code = language.languageCode?.identifier ?? ""
        switch code {
        case "nb", "nn", "no":
            return .norwegian
        case "de":
            return .german
        default:
            return .english
        }
    }

    /// The language code for URLs (e.g., "en", "no", "de")
    var tidexLanguageCode: String {
        tidexLanguage.rawValue
    }
}
