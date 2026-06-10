import SafariServices
import SwiftUI

/// Terms and conditions agreement checkbox with links
struct TermsAgreementView: View {
  @Binding var isAgreed: Bool
  var error: String?

  @State private var safariURL: URL?

  private var termsURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/terms")
  }

  private var privacyURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/privacy")
  }

  var body: some View {
    VStack(alignment: .center, spacing: Spacing.xs) {
      HStack(alignment: .center, spacing: Spacing.xs) {
        checkboxButton
        termsLabel
      }

      if let error, !error.isEmpty {
        Text(error)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexError)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .fullScreenCover(item: $safariURL) { url in
      SafariView(url: url)
        .ignoresSafeArea()
    }
  }

  private var checkboxButton: some View {
    Button(action: { isAgreed.toggle() }) {
      ZStack {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .stroke(checkboxBorderColor, lineWidth: 1.5)
          .frame(width: 20, height: 20)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxs)
              .fill(isAgreed ? Color.tidexBrandPrimary : Color.clear)
          )

        if isAgreed {
          Image(systemName: "checkmark")
            .font(.tidexCaptionStrong)
            .foregroundColor(.tidexTextOnBrand)
        }
      }
      .frame(width: 24, height: 24)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(agreementAccessibilityLabel)
    .accessibilityAddTraits(isAgreed ? .isSelected : [])
    .accessibilityHint(Text(.signupTermsPrefix))
  }

  private var agreementAccessibilityLabel: Text {
    Text(
      "\(String(localized: .signupTermsTermsLink)) \(String(localized: .signupTermsAnd)) \(String(localized: .signupTermsPrivacyLink))"
    )
  }

  private var checkboxBorderColor: Color {
    if error != nil {
      return .tidexError
    }
    return isAgreed ? .tidexBrandPrimary : .tidexBorder
  }

  private var termsLabel: some View {
    // Build the terms text with proper text flow using AttributedString
    Text(termsAttributedString)
      .font(.tidexSubheadline)
      .fixedSize(horizontal: false, vertical: true)
      .multilineTextAlignment(.center)
      .environment(
        \.openURL,
        OpenURLAction { url in
          safariURL = url
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
    termsPart.foregroundColor = .tidexBlue
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
    privacyPart.foregroundColor = .tidexBlue
    privacyPart.underlineStyle = .single
    if let url = privacyURL {
      privacyPart.link = url
    }
    result.append(privacyPart)

    return result
  }
}

// MARK: - Safari View

/// Wrapper for presenting SFSafariViewController in SwiftUI
struct SafariView: UIViewControllerRepresentable {
  let url: URL

  // swiftlint:disable:next explicit_acl
  func makeUIViewController(context _: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  // swiftlint:disable:next explicit_acl no_empty_block
  func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

// MARK: - URL Identifiable Extension

extension URL: @retroactive Identifiable {
  public var id: String { absoluteString }
}

#Preview("Terms Agreement - Unchecked") {
  VStack {
    TermsAgreementView(isAgreed: .constant(false))
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Terms Agreement - Checked") {
  VStack {
    TermsAgreementView(isAgreed: .constant(true))
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Terms Agreement - Error") {
  VStack {
    TermsAgreementView(isAgreed: .constant(false), error: "You must agree to the terms")
  }
  .padding()
  .background(Color.tidexBackground)
}
