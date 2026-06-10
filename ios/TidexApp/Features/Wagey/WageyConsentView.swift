import SafariServices
import SwiftUI

/// Consent view shown before first use of Wagey
/// Explains what data is shared with OpenAI and requires explicit user consent
struct WageyConsentView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  private let ctaButtonHeight: CGFloat = 56  // swiftlint:disable:this type_contents_order
  private let ctaBottomPadding: CGFloat = Spacing.sm  // swiftlint:disable:this type_contents_order
  private let ctaStackSpacing: CGFloat = Spacing.md  // swiftlint:disable:this type_contents_order
  private let ctaFadeStartOffset: CGFloat = Spacing.xl  // swiftlint:disable:this type_contents_order
  private let declineButtonHeight: CGFloat = 24  // swiftlint:disable:this type_contents_order

  private var bottomCTAHeight: CGFloat {  // swiftlint:disable:this type_contents_order
    ctaButtonHeight + ctaStackSpacing + declineButtonHeight + ctaBottomPadding
  }

  private var bottomCTAReservedHeight: CGFloat {  // swiftlint:disable:this type_contents_order
    bottomCTAHeight + ctaFadeStartOffset
  }

  /// Callback when user agrees to data sharing
  let onAgree: () -> Void  // swiftlint:disable:this explicit_acl type_contents_order

  /// Callback when user declines (closes Wagey)
  var onDecline: (() -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order

  /// URL for opening Safari to view the privacy policy
  @State private var safariURL: URL?  // swiftlint:disable:this type_contents_order

  /// OpenAI privacy policy URL
  private static let openAIPrivacyURL = URL(  // swiftlint:disable:this explicit_type_interface
    string: "https://openai.com/policies/privacy-policy"
  )

  /// Tidex privacy policy URL
  private var privacyURL: URL? {  // swiftlint:disable:this type_contents_order
    URL(string: "\(TermsVersion.baseURL)/\(Locale.current.urlLanguageCode)/privacy")
  }

  /// Shared gradient used for hero and agree button
  private static let brandGradient = LinearGradient(  // swiftlint:disable:this explicit_type_interface
    colors: [
      Color(red: 0.35, green: 0.45, blue: 0.95),  // swiftlint:disable:this no_magic_numbers
      Color(red: 0.55, green: 0.35, blue: 0.9),  // swiftlint:disable:this no_magic_numbers
    ],
    startPoint: .leading,
    endPoint: .trailing
  )

  var body: some View {  // swiftlint:disable:this explicit_acl
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        ScrollView {
          VStack(spacing: 0) {
            heroSection

            VStack(spacing: Spacing.xl) {
              descriptionSection
              dataSharedSection
              recipientSection
              linksSection
              withdrawNote
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxxl + bottomCTAReservedHeight)
          }
        }

        bottomFadeOverlay(for: geometry)

        actionButtons
          .frame(maxWidth: .infinity)
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, ctaBottomPadding)
      }
    }
    .background(Color.tidexBackground)
    .ignoresSafeArea(edges: .top)
    .fullScreenCover(item: $safariURL) { url in
      SafariViewConsent(url: url)
        .ignoresSafeArea()
    }
  }

  private func bottomFadeOverlay(for geometry: GeometryProxy) -> some View {  // swiftlint:disable:this line_length type_contents_order
    let bottomInset = geometry.safeAreaInsets.bottom  // swiftlint:disable:this explicit_type_interface

    return LinearGradient(
      stops: [
        .init(color: Color.tidexBackground.opacity(0), location: 0),
        .init(color: Color.tidexBackground.opacity(0.82), location: 0.42),  // swiftlint:disable:this no_magic_numbers
        .init(color: Color.tidexBackground.opacity(0.98), location: 0.68),  // swiftlint:disable:this no_magic_numbers
        .init(color: Color.tidexBackground, location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(height: bottomCTAReservedHeight + bottomInset + Spacing.xl)
    .frame(maxWidth: .infinity)
    .offset(y: bottomInset)
    .ignoresSafeArea(edges: .bottom)
    .allowsHitTesting(false)
  }

  // MARK: - Hero Section

  private var heroSection: some View {
    ZStack {  // swiftlint:disable:this closure_body_length
      Self.brandGradient

      Circle()
        .fill(Color.white.opacity(0.15))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 200, height: 200)  // swiftlint:disable:this no_magic_numbers
        .blur(radius: 50)  // swiftlint:disable:this no_magic_numbers
        .offset(x: -100, y: -30)  // swiftlint:disable:this no_magic_numbers

      Circle()
        .fill(Color.white.opacity(0.1))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 150, height: 150)  // swiftlint:disable:this no_magic_numbers
        .blur(radius: 40)  // swiftlint:disable:this no_magic_numbers
        .offset(x: 120, y: 50)  // swiftlint:disable:this no_magic_numbers

      VStack(spacing: Spacing.mlg) {
        Spacer()
          .frame(height: 60)  // swiftlint:disable:this no_magic_numbers

        ZStack {
          Circle()
            .fill(Color.white.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
            .frame(width: 100, height: 100)
            .blur(radius: 25)  // swiftlint:disable:this no_magic_numbers

          Circle()
            .fill(
              LinearGradient(
                colors: [.white.opacity(0.35), .white.opacity(0.15)],  // swiftlint:disable:this no_magic_numbers
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 80, height: 80)  // swiftlint:disable:this no_magic_numbers

          Image(systemName: "hand.raised.fill")  // swiftlint:disable:this accessibility_label_for_image
            .font(.system(size: 36, weight: .medium))  // swiftlint:disable:this no_magic_numbers
            .foregroundStyle(.white)
        }

        Text(.wageyConsentTitle)
          .font(.tidexAmountLarge)
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)

        Spacer()
          .frame(height: 32)  // swiftlint:disable:this no_magic_numbers
      }
    }
    .frame(minHeight: 280)  // swiftlint:disable:this no_magic_numbers
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
    .background(Color.tidexSurfaceSecondary.opacity(0.5))  // swiftlint:disable:this no_magic_numbers
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)  // swiftlint:disable:this no_magic_numbers
    )
  }

  private func dataRow(icon: String, text: String) -> some View {  // swiftlint:disable:this type_contents_order
    HStack(spacing: Spacing.sm) {
      Image(systemName: icon)  // swiftlint:disable:this accessibility_label_for_image
        .font(.tidexBody)
        .foregroundColor(.tidexBlue)
        .frame(width: 24)  // swiftlint:disable:this no_magic_numbers

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
    VStack(spacing: 0) {  // swiftlint:disable:this closure_body_length
      Button {
        if let url = privacyURL {
          safariURL = url
        }
      } label: {
        HStack(alignment: .top, spacing: Spacing.sm) {
          Image(systemName: "shield")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexBody)
            .frame(width: 20, alignment: .leading)  // swiftlint:disable:this no_magic_numbers
          Text(.wageyConsentPrivacyLink)
            .font(.tidexBody)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "arrow.up.right")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(.tidexTextPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.msm)
      }

      Divider()
        .background(Color.tidexBorderSubtle)

      Button {
        if let url = Self.openAIPrivacyURL {
          safariURL = url
        }
      } label: {
        HStack(alignment: .top, spacing: Spacing.sm) {
          Image(systemName: "lock.shield")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexBody)
            .frame(width: 20, alignment: .leading)  // swiftlint:disable:this no_magic_numbers
          Text(.wageyConsentProviderPrivacyLink)
            .font(.tidexBody)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "arrow.up.right")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    VStack(spacing: ctaStackSpacing) {
      Button {
        Haptics.play(.success)
        onAgree()
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "checkmark.shield.fill")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexLabelStrong)

          Text(.wageyConsentAgreeButton)
            .font(.tidexHeadline)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ctaButtonHeight)
        .foregroundStyle(.white)
        .background(Self.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
        .shadow(color: Color(red: 0.45, green: 0.4, blue: 0.9).opacity(0.3), radius: 12, y: 6)  // swiftlint:disable:this line_length no_magic_numbers
      }

      Button {
        onDecline?()
      } label: {
        Text(.wageyConsentDeclineButton)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .frame(height: declineButtonHeight)
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Safari View

private struct SafariViewConsent: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context _: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  func updateUIViewController(
    _: SFSafariViewController,
    context _: Context
  ) {}  // swiftlint:disable:this no_empty_block
}

// MARK: - Preview

#Preview {
  WageyConsentView(
    onAgree: { print("Agreed") },  // swiftlint:disable:this no_direct_print
    onDecline: { print("Declined") }  // swiftlint:disable:this no_direct_print
  )
}
