import SwiftUI

/// Terms and conditions agreement checkbox with links
struct TermsAgreementView: View {
    @Binding var isAgreed: Bool
    var error: String?

    @Environment(\.localization) private var localization
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false

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
        .sheet(isPresented: $showTermsSheet) {
            LegalDocumentSheet(
                title: localization.string("legal.termsOfService"),
                documentType: .termsOfService
            )
        }
        .sheet(isPresented: $showPrivacySheet) {
            LegalDocumentSheet(
                title: localization.string("legal.privacyPolicy"),
                documentType: .privacyPolicy
            )
        }
    }

    private var checkboxBorderColor: Color {
        if error != nil {
            return .tidexError
        }
        return isAgreed ? .tidexBrandPrimary : .tidexBorder
    }

    private var termsLabel: some View {
        // Build the terms text with tappable links
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(localization.string("signup.terms.prefix"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)

                Button(action: { showTermsSheet = true }) {
                    Text(localization.string("signup.terms.termsLink"))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexBlue)
                        .underline()
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                Text(localization.string("signup.terms.and"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)

                Button(action: { showPrivacySheet = true }) {
                    Text(localization.string("signup.terms.privacyLink"))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexBlue)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Legal Document Sheet

/// Sheet view for displaying legal documents
struct LegalDocumentSheet: View {
    let title: String
    let documentType: LegalDocumentType

    @Environment(\.dismiss) private var dismiss
    @Environment(\.localization) private var localization

    enum LegalDocumentType {
        case termsOfService
        case privacyPolicy
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(documentContent)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextPrimary)
                        .lineSpacing(4)
                }
                .padding(20)
            }
            .background(Color.tidexDarkBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.tidexTextSecondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var documentContent: String {
        switch documentType {
        case .termsOfService:
            return localization.string("legal.termsOfServiceContent")
        case .privacyPolicy:
            return localization.string("legal.privacyPolicyContent")
        }
    }
}

#Preview("Terms Agreement - Unchecked") {
    VStack {
        TermsAgreementView(isAgreed: .constant(false))
    }
    .padding()
    .background(Color.tidexDarkBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Terms Agreement - Checked") {
    VStack {
        TermsAgreementView(isAgreed: .constant(true))
    }
    .padding()
    .background(Color.tidexDarkBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Terms Agreement - Error") {
    VStack {
        TermsAgreementView(isAgreed: .constant(false), error: "You must agree to the terms")
    }
    .padding()
    .background(Color.tidexDarkBackground)
    .environment(\.localization, LocalizationManager.shared)
}
