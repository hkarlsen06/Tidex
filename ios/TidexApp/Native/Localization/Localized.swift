import SwiftUI

extension Locale {
    var tidexIsNorwegian: Bool {
        let code = language.languageCode?.identifier ?? language.languageCode?.identifier ?? ""
        return code == "nb" || code == "nn" || code == "no"
    }

    var tidexLanguageCode: String {
        tidexIsNorwegian ? "no" : "en"
    }
}
