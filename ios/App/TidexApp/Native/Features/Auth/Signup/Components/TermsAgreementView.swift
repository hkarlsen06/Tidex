import SafariServices
import SwiftUI

/// Terms and conditions agreement checkbox with links
struct TermsAgreementView: View {
    @Binding var isAgreed: Bool
    var error: String?

    @Environment(\.localization) private var localization
    @State private var safariURL: URL?

    private var termsURL: URL? {
        URL(string: "https://www.tidex.no/\(localization.currentLocale.rawValue)/terms")
    }

    private var privacyURL: URL? {
        URL(string: "https://www.tidex.no/\(localization.currentLocale.rawValue)/privacy")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Checkbox with label
            Button(action: {
                isAgreed.toggle()
            }) {
                HStack(alignment: .top, spacing: 12) {
                    // Checkbox
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(checkboxBorderColor, lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isAgreed ? Color.tidexBrandPrimary : Color.clear)
                            )

                        if isAgreed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                    // Label with links
                    termsLabel
                }
            }
            .buttonStyle(.plain)

            // Error message
            if let error = error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.tidexError)
            }
        }
        .fullScreenCover(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    private var checkboxBorderColor: Color {
        if error != nil {
            return .tidexError
        }
        return isAgreed ? .tidexBrandPrimary : .tidexBorder
    }

    private var termsLabel: some View {
        // Build the terms text with tappable links on a single line
        HStack(spacing: 4) {
            Text(localization.string("signup.terms.prefix"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Button(action: { safariURL = termsURL }) {
                Text(localization.string("signup.terms.termsLink"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexBlue)
                    .underline()
            }
            .buttonStyle(.plain)

            Text(localization.string("signup.terms.and"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Button(action: { safariURL = privacyURL }) {
                Text(localization.string("signup.terms.privacyLink"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexBlue)
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Safari View

/// Wrapper for presenting SFSafariViewController in SwiftUI
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
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
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Terms Agreement - Checked") {
    VStack {
        TermsAgreementView(isAgreed: .constant(true))
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Terms Agreement - Error") {
    VStack {
        TermsAgreementView(isAgreed: .constant(false), error: "You must agree to the terms")
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
