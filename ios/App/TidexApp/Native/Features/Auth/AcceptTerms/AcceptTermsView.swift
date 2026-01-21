import os.log
import SafariServices
import Supabase
import SwiftUI

private let logger = Logger(subsystem: "no.tidex.app", category: "AcceptTerms")

/// Screen shown when user needs to accept (or re-accept) terms of service
/// Mirrors the web app's `/accept-terms` page behavior
struct AcceptTermsView: View {
    let isUpdate: Bool
    let coordinator: AppCoordinator

    @Environment(\.localization) private var localization
    @State private var isProcessing = false
    @State private var error: String?
    @State private var safariURL: URL?

    /// Terms URL - uses locale-specific path for proper language display
    private var termsURL: URL? {
        URL(string: "\(TermsVersion.baseURL)/\(localization.currentLocale.rawValue)/terms")
    }

    /// Privacy URL - uses locale-specific path for proper language display
    private var privacyURL: URL? {
        URL(string: "\(TermsVersion.baseURL)/\(localization.currentLocale.rawValue)/privacy")
    }

    var body: some View {
        ZStack {
            Color.tidexBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Logo
                    Image("Splash")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .padding(.top, 40)

                    // Content card
                    VStack(spacing: 24) {
                        // Title and description
                        VStack(spacing: 12) {
                            Text(isUpdate
                                 ? localization.string("acceptTerms.updated.title")
                                 : localization.string("acceptTerms.title"))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.tidexTextPrimary)
                                .multilineTextAlignment(.center)

                            Text(isUpdate
                                 ? localization.string("acceptTerms.updated.description")
                                 : localization.string("acceptTerms.description"))
                                .font(.system(size: 16))
                                .foregroundColor(.tidexTextSecondary)
                                .multilineTextAlignment(.center)
                        }

                        // Explanation text
                        Text(isUpdate
                             ? localization.string("acceptTerms.updated.explanation")
                             : localization.string("acceptTerms.explanation"))
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        // Error message
                        if let error = error {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.tidexError)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.tidexError.opacity(0.1))
                                )
                        }

                        // Legal links
                        VStack(spacing: 12) {
                            Button {
                                if let url = termsURL {
                                    safariURL = url
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text(localization.string("acceptTerms.viewTerms"))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                }
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.tidexBlue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.tidexSurfaceSecondary)
                                )
                            }
                            .disabled(isProcessing)

                            Button {
                                if let url = privacyURL {
                                    safariURL = url
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "shield")
                                    Text(localization.string("acceptTerms.viewPrivacy"))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                }
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.tidexBlue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.tidexSurfaceSecondary)
                                )
                            }
                            .disabled(isProcessing)
                        }

                        // Action buttons
                        VStack(spacing: 12) {
                            // Accept button
                            Button {
                                acceptTerms()
                            } label: {
                                HStack {
                                    if isProcessing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                    Text(localization.string("acceptTerms.acceptButton"))
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.tidexBrandPrimary)
                                )
                            }
                            .disabled(isProcessing)

                            // Decline button
                            Button {
                                declineTerms()
                            } label: {
                                Text(localization.string("acceptTerms.declineButton"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.tidexTextMuted)
                            }
                            .disabled(isProcessing)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.tidexSurfacePrimary)
                    )
                    .adaptiveFormWidth()
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(item: $safariURL) { url in
            SafariViewAcceptTerms(url: url)
                .ignoresSafeArea()
        }
    }

    private func acceptTerms() {
        isProcessing = true
        error = nil

        Task {
            do {
                // Update user metadata with terms acceptance timestamp
                _ = try await supabase.auth.update(user: UserAttributes(
                    data: ["terms_accepted_at": .string(ISO8601DateFormatter().string(from: Date()))]
                ))

                // Refresh session to get updated JWT
                _ = try await supabase.auth.refreshSession()

                // Notify coordinator that terms were accepted
                await MainActor.run {
                    coordinator.handleTermsAccepted()
                }
            } catch {
                await MainActor.run {
                    self.error = localization.string("acceptTerms.errors.updateFailed")
                    self.isProcessing = false
                }
                logger.error("Failed to update terms acceptance: \(error.localizedDescription)")
            }
        }
    }

    private func declineTerms() {
        isProcessing = true

        Task {
            await coordinator.handleTermsDeclined()
        }
    }
}

// MARK: - Safari View (local copy to avoid import issues)

/// Wrapper for presenting SFSafariViewController in SwiftUI
private struct SafariViewAcceptTerms: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview("Accept Terms - Initial") {
    AcceptTermsView(isUpdate: false, coordinator: AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}

#Preview("Accept Terms - Update") {
    AcceptTermsView(isUpdate: true, coordinator: AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
