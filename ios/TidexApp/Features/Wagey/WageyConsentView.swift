import SafariServices
import SwiftUI

/// Consent view shown before first use of Wagey
/// Explains what data is shared with Anthropic and requires explicit user consent
struct WageyConsentView: View {
  /// Callback when user agrees to data sharing
  let onAgree: () -> Void

  /// Callback when user declines (closes Wagey)
  var onDecline: (() -> Void)?

  /// URL for opening Safari to view the privacy policy
  @State private var safariURL: URL?

  /// Anthropic privacy policy URL
  private static let anthropicPrivacyURL = URL(string: "https://www.anthropic.com/privacy")

  /// Tidex privacy policy URL
  private var privacyURL: URL? {
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/privacy")
  }

  /// Shared gradient used for hero and agree button
  private static let brandGradient = LinearGradient(
    colors: [
      Color(red: 0.35, green: 0.45, blue: 0.95),
      Color(red: 0.55, green: 0.35, blue: 0.9),
    ],
    startPoint: .leading,
    endPoint: .trailing
  )

  var body: some View {
    ZStack(alignment: .topTrailing) {
      ScrollView {
        VStack(spacing: 0) {
          heroSection

          VStack(spacing: Spacing.xl) {
            descriptionSection
            dataSharedSection
            recipientSection
            linksSection
            withdrawNote
            actionButtons
          }
          .padding(.horizontal, Spacing.lg)
          .padding(.top, Spacing.xl)
          .padding(.bottom, Spacing.xxxl)
        }
      }
      .background(Color.tidexBackground)
      .ignoresSafeArea(edges: .top)

      // Close button overlay
      if let onDecline = onDecline {
        Button {
          onDecline()
        } label: {
          Image(systemName: "xmark")
            .font(.tidexButton)
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.2))
            .clipShape(Circle())
            .contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.top, Spacing.md)
        .padding(.trailing, Spacing.mlg)
      }
    }
    .fullScreenCover(item: $safariURL) { url in
      SafariViewConsent(url: url)
        .ignoresSafeArea()
    }
  }

  // MARK: - Hero Section

  private var heroSection: some View {
    ZStack {
      Self.brandGradient

      Circle()
        .fill(Color.white.opacity(0.15))
        .frame(width: 200, height: 200)
        .blur(radius: 50)
        .offset(x: -100, y: -30)

      Circle()
        .fill(Color.white.opacity(0.1))
        .frame(width: 150, height: 150)
        .blur(radius: 40)
        .offset(x: 120, y: 50)

      VStack(spacing: Spacing.mlg) {
        Spacer()
          .frame(height: 60)

        ZStack {
          Circle()
            .fill(Color.white.opacity(0.3))
            .frame(width: 100, height: 100)
            .blur(radius: 25)

          Circle()
            .fill(
              LinearGradient(
                colors: [.white.opacity(0.35), .white.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 80, height: 80)

          Image(systemName: "hand.raised.fill")
            .font(.system(size: 36, weight: .medium))
            .foregroundStyle(.white)
        }

        Text(.wageyConsentTitle)
          .font(.tidexAmountLarge)
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)

        Spacer()
          .frame(height: 32)
      }
    }
    .frame(minHeight: 280)
  }

  // MARK: - Description

  private var descriptionSection: some View {
    Text(.wageyConsentDescription)
      .font(.tidexBody)
      .foregroundColor(.tidexTextSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Data Shared List

  private var dataSharedSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.wageyConsentDataSharedTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      dataRow(icon: "text.bubble", text: String(localized: .wageyConsentDataSharedMessages))
      dataRow(icon: "person", text: String(localized: .wageyConsentDataSharedName))
      dataRow(icon: "calendar.badge.clock", text: String(localized: .wageyConsentDataSharedShifts))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
    )
  }

  private func dataRow(icon: String, text: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: icon)
        .font(.tidexBody)
        .foregroundColor(.tidexBlue)
        .frame(width: 24)

      Text(text)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Recipient Info

  private var recipientSection: some View {
    Text(.wageyConsentRecipient)
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Links

  private var linksSection: some View {
    VStack(spacing: 0) {
      Button {
        if let url = privacyURL {
          safariURL = url
        }
      } label: {
        HStack {
          Image(systemName: "shield")
            .font(.tidexBody)
          Text(.wageyConsentPrivacyLink)
            .font(.tidexBody)
          Spacer()
          Image(systemName: "arrow.up.right")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        .foregroundColor(.tidexTextPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.msm)
      }

      Divider()
        .background(Color.tidexBorderSubtle)

      Button {
        if let url = Self.anthropicPrivacyURL {
          safariURL = url
        }
      } label: {
        HStack {
          Image(systemName: "lock.shield")
            .font(.tidexBody)
          Text(.wageyConsentAnthropicPrivacyLink)
            .font(.tidexBody)
          Spacer()
          Image(systemName: "arrow.up.right")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        .foregroundColor(.tidexTextPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.msm)
      }
    }
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  // MARK: - Withdraw Note

  private var withdrawNote: some View {
    Text(.wageyConsentWithdrawNote)
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
      .multilineTextAlignment(.center)
  }

  // MARK: - Action Buttons

  private var actionButtons: some View {
    VStack(spacing: Spacing.md) {
      Button {
        Haptics.play(.success)
        onAgree()
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "checkmark.shield.fill")
            .font(.tidexLabelStrong)

          Text(.wageyConsentAgreeButton)
            .font(.tidexHeadline)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .foregroundStyle(.white)
        .background(Self.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
        .shadow(color: Color(red: 0.45, green: 0.4, blue: 0.9).opacity(0.3), radius: 12, y: 6)
      }

      Button {
        onDecline?()
      } label: {
        Text(.wageyConsentDeclineButton)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Safari View

private struct SafariViewConsent: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
  WageyConsentView(
    onAgree: { print("Agreed") },
    onDecline: { print("Declined") }
  )
}
