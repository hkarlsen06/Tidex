import SwiftUI

/// Says that continuing accepts the Terms of Service and Privacy Policy, with links to both.
/// Signup records `terms_accepted_at` when the user continues.
struct TermsAgreementView: View {
  @Environment(\.openURL) private var openURL

  private var termsURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/terms")
  }

  private var privacyURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/privacy")
  }

  var body: some View {
    Text(termsAttributedString)
      .font(.tidexFootnote)
      .fixedSize(horizontal: false, vertical: true)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
      // The links are also actions, so VoiceOver and Voice Control do not need the links rotor.
      .accessibilityAction(named: Text(.acceptTermsViewTerms)) {
        if let termsURL { openURL(termsURL, prefersInApp: true) }
      }
      .accessibilityAction(named: Text(.acceptTermsViewPrivacy)) {
        if let privacyURL { openURL(privacyURL, prefersInApp: true) }
      }
      .environment(
        \.openURL,
        OpenURLAction { url in
          openURL(url, prefersInApp: true)
          return .handled
        })
  }

  private var termsAttributedString: AttributedString {
    let prefix = String(localized: .signupTermsPrefix)
    let termsLinkText = String(localized: .signupTermsTermsLink)
    let andText = String(localized: .signupTermsAnd)
    let privacyLinkText = String(localized: .signupTermsPrivacyLink)

    var result = AttributedString()

    // Prefix text
    var prefixPart = AttributedString(prefix + " ")
    prefixPart.foregroundColor = .tidexTextSecondary
    result.append(prefixPart)

    // Terms link
    var termsPart = AttributedString(termsLinkText)
    termsPart.foregroundColor = .tidexBlueText
    termsPart.underlineStyle = .single
    if let url = termsURL {
      termsPart.link = url
    }
    result.append(termsPart)

    var andPart = AttributedString(" " + andText + " ")
    andPart.foregroundColor = .tidexTextSecondary
    result.append(andPart)

    // Privacy link
    var privacyPart = AttributedString(privacyLinkText)
    privacyPart.foregroundColor = .tidexBlueText
    privacyPart.underlineStyle = .single
    if let url = privacyURL {
      privacyPart.link = url
    }
    result.append(privacyPart)

    return result
  }
}

#Preview("Terms Agreement") {
  TermsAgreementView()
    .padding()
    .background(Color.tidexBackground)
}
