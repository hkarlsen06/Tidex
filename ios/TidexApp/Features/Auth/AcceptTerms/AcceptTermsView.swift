import os.log
import SafariServices
import Supabase
import SwiftUI

private let kAcceptTermsLogger: Logger = Logger(subsystem: "no.tidex.app", category: "AcceptTerms")

// MARK: - Safari View (local copy to avoid import issues)

/// Wrapper for presenting SFSafariViewController in SwiftUI
internal struct SafariViewAcceptTerms: UIViewControllerRepresentable {
  private let url: URL

  internal init(url: URL) {
    self.url = url
  }

  internal func makeUIViewController(context _: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  internal func updateUIViewController(_: SFSafariViewController, context _: Context) {
    _ = url
  }
}

/// Screen shown when user needs to accept (or re-accept) terms of service
/// Mirrors the web app's `/accept-terms` page behavior
internal struct AcceptTermsView: View {
  internal let isUpdate: Bool
  internal let coordinator: AppCoordinator

  @State private var isProcessing: Bool = false
  @State private var error: String?
  @State private var safariURL: URL?

  private let verticalSpacerLength: CGFloat = 60
  private let iconBackgroundSize: CGFloat = 80
  private let documentIconSize: CGFloat = 36
  private let linkIconWidth: CGFloat = 20
  private let iconBackgroundOpacity: Double = 0.1

  /// Terms URL - uses locale-specific path for proper language display
  private var termsURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/terms")
  }

  /// Privacy URL - uses locale-specific path for proper language display
  private var privacyURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/privacy")
  }

  internal var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          Spacer(minLength: verticalSpacerLength)

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

          Spacer(minLength: verticalSpacerLength)
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
          .fill(Color.tidexBlue.opacity(iconBackgroundOpacity))
          .frame(width: iconBackgroundSize, height: iconBackgroundSize)

        Image(systemName: "doc.text.fill")
          .font(.system(size: documentIconSize))
          .foregroundColor(.tidexBlue)
          .accessibilityHidden(true)
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
      legalLinkButton(
        title: Text(.acceptTermsViewTerms),
        systemImage: "doc.text",
        url: termsURL
      )

      Divider()
        .background(Color.tidexBorderSubtle)

      legalLinkButton(
        title: Text(.acceptTermsViewPrivacy),
        systemImage: "shield",
        url: privacyURL
      )
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

  private func legalLinkButton(
    title: Text,
    systemImage: String,
    url: URL?
  ) -> some View {
    Button {
      if let url {
        safariURL = url
      }
    } label: {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Image(systemName: systemImage)
          .font(.tidexBody)
          .frame(width: linkIconWidth, alignment: .leading)
          .accessibilityHidden(true)
        title
          .font(.tidexBody)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "arrow.up.right")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .foregroundColor(.tidexTextPrimary)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.msm)
    }
    .disabled(isProcessing)
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
          )
        )

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
        kAcceptTermsLogger.error("Failed to update terms acceptance: \(error.localizedDescription)")
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

#Preview("Accept Terms - Initial") {
  AcceptTermsView(isUpdate: false, coordinator: AppCoordinator.shared)
}

#Preview("Accept Terms - Update") {
  AcceptTermsView(isUpdate: true, coordinator: AppCoordinator.shared)
}
