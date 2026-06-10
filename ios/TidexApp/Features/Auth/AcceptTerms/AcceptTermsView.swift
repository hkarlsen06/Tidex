import SafariServices
import Supabase
import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "AcceptTerms")

/// Screen shown when user needs to accept (or re-accept) terms of service
/// Mirrors the web app's `/accept-terms` page behavior
struct AcceptTermsView: View {
  let isUpdate: Bool
  let coordinator: AppCoordinator

  @State private var isProcessing = false
  @State private var error: String?
  @State private var safariURL: URL?

  /// Terms URL - uses locale-specific path for proper language display
  private var termsURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/terms")
  }

  /// Privacy URL - uses locale-specific path for proper language display
  private var privacyURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/privacy")
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          Spacer(minLength: 60)

          // Header section
          headerSection
            .padding(.bottom, Spacing.xxl)

          // Main content
          VStack(spacing: Spacing.lg) {
            // Error banner
            if let error {
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
          .padding(.horizontal, Spacing.lg)

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
    VStack(spacing: Spacing.md) {
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
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)
    }
  }

  // MARK: - Instructions Section

  private var instructionsSection: some View {
    VStack(spacing: Spacing.xs) {
      Text(
        isUpdate
          ? String(localized: .acceptTermsUpdatedTitle)
          : String(localized: .acceptTermsTitle)
      )
      .font(.tidexTitle)
      .foregroundColor(.tidexTextPrimary)
      .multilineTextAlignment(.center)

      Text(
        isUpdate
          ? String(localized: .acceptTermsUpdatedDescription)
          : String(localized: .acceptTermsDescription)
      )
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextSecondary)
      .multilineTextAlignment(.center)

      Text(
        isUpdate
          ? String(localized: .acceptTermsUpdatedExplanation)
          : String(localized: .acceptTermsExplanation)
      )
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
      .multilineTextAlignment(.center)
      .padding(.top, Spacing.xxs)
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
        HStack(alignment: .top, spacing: Spacing.sm) {
          Image(systemName: "doc.text")
            .font(.tidexBody)
            .frame(width: 20, alignment: .leading)
          Text(.acceptTermsViewTerms)
            .font(.tidexBody)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "arrow.up.right")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(.tidexTextPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.msm)
      }
      .disabled(isProcessing)

      Divider()
        .background(Color.tidexBorderSubtle)

      Button {
        if let url = privacyURL {
          safariURL = url
        }
      } label: {
        HStack(alignment: .top, spacing: Spacing.sm) {
          Image(systemName: "shield")
            .font(.tidexBody)
            .frame(width: 20, alignment: .leading)
          Text(.acceptTermsViewPrivacy)
            .font(.tidexBody)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "arrow.up.right")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(.tidexTextPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.msm)
      }
      .disabled(isProcessing)
    }
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  // MARK: - Action Buttons Section

  private var actionButtonsSection: some View {
    VStack(spacing: Spacing.md) {
      // Accept button
      PrimaryButton(
        title: String(localized: .acceptTermsAcceptButton),
        action: { acceptTerms() },
        isLoading: isProcessing
      )

      // Decline button
      Button {
        declineTerms()
      } label: {
        Text(.acceptTermsDeclineButton)
          .font(.tidexSubheadline)
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
        _ = try await supabase.auth.update(
          user: UserAttributes(
            data: ["terms_accepted_at": .string(ISO8601DateFormatter().string(from: Date()))]
          ))

        // Refresh session to get updated JWT via serialized auth path
        _ = try await AuthSessionManager.shared.forceRefresh()

        // Notify coordinator that terms were accepted
        await MainActor.run {
          coordinator.handleTermsAccepted()
        }
      } catch {
        await MainActor.run {
          self.error = String(localized: .acceptTermsErrorsUpdateFailed)
          isProcessing = false
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

  func makeUIViewController(context _: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  // swiftlint:disable:next no_empty_block
  func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

#Preview("Accept Terms - Initial") {
  AcceptTermsView(isUpdate: false, coordinator: AppCoordinator.shared)
}

#Preview("Accept Terms - Update") {
  AcceptTermsView(isUpdate: true, coordinator: AppCoordinator.shared)
}
