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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    // Header section
                    headerSection
                        .padding(.bottom, 40)

                    // Main content
                    VStack(spacing: 24) {
                        // Error banner
                        if let error = error {
                            ErrorBanner(
                                message: error,
                                onDismiss: { self.error = nil }
                            )
                        }

                        // Instructions
                        instructionsSection

                        // Legal links
                        legalLinksSection

                        // Action buttons
                        actionButtonsSection
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 60)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.tidexBackground)
        .fullScreenCover(item: $safariURL) { url in
            SafariViewAcceptTerms(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Document icon for terms
            ZStack {
                Circle()
                    .fill(Color.tidexBlue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.tidexBlue)
            }

            // Title
            Text("Tidex")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(spacing: 8) {
            Text(isUpdate
                 ? localization.string("acceptTerms.updated.title")
                 : localization.string("acceptTerms.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

            Text(isUpdate
                 ? localization.string("acceptTerms.updated.description")
                 : localization.string("acceptTerms.description"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Text(isUpdate
                 ? localization.string("acceptTerms.updated.explanation")
                 : localization.string("acceptTerms.explanation"))
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    // MARK: - Legal Links Section

    private var legalLinksSection: some View {
        VStack(spacing: 0) {
            Button {
                if let url = termsURL {
                    safariURL = url
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                    Text(localization.string("acceptTerms.viewTerms"))
                        .font(.system(size: 17))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(.tidexTextMuted)
                }
                .foregroundColor(.tidexTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .disabled(isProcessing)

            Divider()
                .background(Color.tidexBorderSubtle)

            Button {
                if let url = privacyURL {
                    safariURL = url
                }
            } label: {
                HStack {
                    Image(systemName: "shield")
                        .font(.system(size: 16))
                    Text(localization.string("acceptTerms.viewPrivacy"))
                        .font(.system(size: 17))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundColor(.tidexTextMuted)
                }
                .foregroundColor(.tidexTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .disabled(isProcessing)
        }
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Accept button
            PrimaryButton(
                title: localization.string("acceptTerms.acceptButton"),
                action: { acceptTerms() },
                isLoading: isProcessing
            )

            // Decline button
            Button {
                declineTerms()
            } label: {
                Text(localization.string("acceptTerms.declineButton"))
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
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
