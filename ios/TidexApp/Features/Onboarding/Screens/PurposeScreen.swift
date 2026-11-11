import SwiftUI

/// Entry screen for the initial post-auth onboarding flow.
/// Uses product-style previews instead of abstract option cards to explain the two paths.
/// The friends choice saves from here, so this screen shows that save's progress and errors.
struct PurposeScreen: View {
  let currency: String
  let friendsSaveStatus: OnboardingSaveManager.SaveStatus
  let onSelectPaySetup: () -> Void
  let onSelectFriendsOnly: () -> Void

  private var isSavingFriends: Bool {
    friendsSaveStatus == .saving
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        Spacer()
          .frame(height: 52)

        header

        Spacer(minLength: Spacing.lg)

        previewShowcase
          .padding(.horizontal, Spacing.lg)
          .adaptiveContentWidth()

        Spacer(minLength: Spacing.lg)

        if case .error(let message) = friendsSaveStatus {
          friendsErrorBanner(message: message)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)
            .adaptiveContentWidth()
        }

        bottomCTASection
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, Spacing.xl)
          .adaptiveContentWidth()
          .disabled(isSavingFriends)
      }
      .frame(maxWidth: .infinity)
      .scrollsOnOverflow()
    }
    .onChange(of: friendsSaveStatus) { _, status in
      if case .error(let message) = status {
        AccessibilityNotification.Announcement(message).post()
      }
    }
  }

  @ViewBuilder
  private var header: some View {
    VStack(spacing: Spacing.sm) {
      Text(.onboardingPostAuthPurposeTitle)
        .font(.tidexScreenTitle)
        .foregroundStyle(Color.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(.onboardingPostAuthPurposeSubtitle)
        .font(.tidexBody)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Spacing.xl)
    .adaptiveContentWidth()
  }

  @ViewBuilder
  private var previewShowcase: some View {
    VStack(spacing: Spacing.lg) {
      sectionDivider

      VStack(spacing: Spacing.sm) {
        PreviewSection(
          title: String(localized: .onboardingPostAuthPurposePayPreviewTitle),
          previewTopOffset: Spacing.xxs
        ) {
          PayPreviewCard(currency: currency)
        }

        PreviewSection(
          title: String(localized: .onboardingPostAuthPurposeFriendsPreviewTitle),
          previewTopOffset: Spacing.xxs
        ) {
          FriendsPreviewCard()
        }
      }
      .frame(maxWidth: .infinity)

      sectionDivider
    }
    .padding(.vertical, Spacing.md)
    .background {
      LinearGradient(
        colors: [
          .clear,
          Color.tidexBlue.opacity(0.08),
          .clear,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .mask {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .white.opacity(0.03), location: 0.03),
            .init(color: .white.opacity(0.1), location: 0.06),
            .init(color: .white.opacity(0.24), location: 0.1),
            .init(color: .white.opacity(0.55), location: 0.15),
            .init(color: .white, location: 0.22),
            .init(color: .white, location: 0.78),
            .init(color: .white.opacity(0.55), location: 0.85),
            .init(color: .white.opacity(0.24), location: 0.9),
            .init(color: .white.opacity(0.1), location: 0.94),
            .init(color: .white.opacity(0.03), location: 0.97),
            .init(color: .clear, location: 1),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      }
    }
  }

  private var sectionDivider: some View {
    Rectangle()
      .fill(
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: Color.tidexBorderSubtle.opacity(0.16), location: 0.04),
            .init(color: Color.tidexBorderSubtle.opacity(0.82), location: 0.1),
            .init(color: Color.tidexBorderSubtle.opacity(0.82), location: 0.9),
            .init(color: Color.tidexBorderSubtle.opacity(0.16), location: 0.96),
            .init(color: .clear, location: 1),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .frame(height: 1)
  }

  /// One line over the buttons. Tapping the friends button again retries.
  private func friendsErrorBanner(message: String) -> some View {
    Label {
      Text(message)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color.tidexError)
    }
    .font(.tidexSubheadline)
    .foregroundStyle(Color.tidexTextSecondary)
    .frame(maxWidth: .infinity, alignment: .center)
  }

  /// The friends choice saves from this screen, so its button shows a spinner while it saves.
  private var friendsButtonTitle: some View {
    Text(.onboardingPostAuthPurposeFriendsOptionTitle)
      .font(.tidexBodyMedium)
      .foregroundStyle(Color.tidexTextPrimary)
      .multilineTextAlignment(.center)
      .opacity(isSavingFriends ? 0 : 1)
      .overlay {
        if isSavingFriends {
          ProgressView()
            .tint(.tidexBlue)
        }
      }
  }

  @ViewBuilder
  private var bottomCTASection: some View {
    VStack(spacing: Spacing.md) {
      OnboardingButton(
        title: String(localized: .onboardingPostAuthPurposePayOptionTitle),
        action: {
          Haptics.play(.success)
          onSelectPaySetup()
        }
      )

      Button(action: {
        Haptics.play(.light)
        onSelectFriendsOnly()
      }) {
        friendsButtonTitle
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.xs)
          .frame(minHeight: 54)
          .background(Color.tidexSurfaceSecondary)
          .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
              .stroke(Color.tidexBorder, lineWidth: 1)
          }
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
      }
      .buttonStyle(.plain)
    }
  }
}

private struct PreviewSection<Content: View>: View {
  let title: String
  let previewTopOffset: CGFloat
  @ViewBuilder let content: Content

  private let previewScale: CGFloat = 0.9

  init(
    title: String,
    previewTopOffset: CGFloat,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.previewTopOffset = previewTopOffset
    self.content = content()
  }

  var body: some View {
    VStack(spacing: Spacing.sm) {
      Text(title)
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)

      content
        .scaleEffect(previewScale, anchor: .top)
        .opacity(0.68)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, -previewTopOffset)
        .accessibilityHidden(true)
    }
  }
}

/// An eight-hour shift tomorrow at the currency's default hourly wage, with evening supplements.
private struct PayPreviewCard: View {
  let currency: String

  var body: some View {
    FeaturedShiftCard(
      shift: sampleShift,
      isToday: false,
      isBestShift: true,
      countdownText: nil,
      progress: nil,
      showIncreaseHighlight: false,
      showFooter: false,
      surfaceStyle: .example
    )
    .userCurrency(currency)
    .allowsHitTesting(false)
  }

  private var sampleShift: ShiftWithComputations {
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    let hours = 8.0
    let basePay = hours * CurrencyConfig.get(currency).wageRangeTier.defaultValue
    let supplementPay = (basePay * 0.14).rounded()
    let row = ShiftRow(
      id: "purpose-pay-preview",
      user_id: "preview-user",
      shift_date: tomorrow.toISODateString(),
      start_time: "08:00",
      end_time: "16:00",
      custom_supplements: nil
    )

    let computed = ShiftComputed(
      id: row.id,
      durationHours: hours,
      paidHours: hours,
      basePay: basePay,
      supplementPay: supplementPay,
      gross: basePay + supplementPay,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    )

    return ShiftWithComputations(
      shift: row,
      computed: computed,
      taxEnabled: false,
      taxPercentage: 0
    )
  }
}

private struct FriendsPreviewCard: View {
  var body: some View {
    FriendCard(
      sharer: sampleSharer,
      preview: nil,
      messagePreview: sampleMessagePreview,
      isTyping: false,
      isSelected: false,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {},
      surfaceStyle: .example
    )
    .environment(\.userCurrency, "kr")
    .allowsHitTesting(false)
  }

  private var sampleSharer: SharedUser {
    SharedUser(
      id: "purpose-friends-preview",
      email: "ella@example.com",
      phone: nil,
      firstName: "Ella",
      profilePictureUrl: nil,
      oauthAvatarUrl: nil,
      sharedAt: "2026-03-20",
      showEarnings: true,
      hidden: false
    )
  }

  private var sampleMessagePreview: FriendCardMessagePreview {
    FriendCardMessagePreview(
      text: String(localized: .onboardingPostAuthPurposeFriendsPreviewMessage),
      timestamp: Date().addingTimeInterval(-900),
      state: .incomingUnread
    )
  }

}

#Preview {
  PurposeScreen(
    currency: "kr",
    friendsSaveStatus: .idle,
    onSelectPaySetup: {},
    onSelectFriendsOnly: {}
  )
}
