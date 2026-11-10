import SwiftUI

/// First setup step. Two choices of equal weight: work out pay, or follow friends' shifts.
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
    VStack(spacing: Spacing.xl) {
      header

      VStack(spacing: Spacing.md) {
        PurposeCard(
          title: .onboardingPostAuthPurposePayOptionTitle,
          message: .onboardingPostAuthPurposePayMessage,
          isBusy: false,
          action: onSelectPaySetup
        ) {
          PayExampleCard(currency: currency)
        }

        PurposeCard(
          title: .onboardingPostAuthPurposeFriendsOptionTitle,
          message: .onboardingPostAuthPurposeFriendsMessage,
          isBusy: isSavingFriends,
          action: onSelectFriendsOnly
        ) {
          FriendExampleCard()
        }

        if case .error(let message) = friendsSaveStatus {
          friendsErrorBanner(message: message)
        }
      }
      .disabled(isSavingFriends)
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.xl)
    .adaptiveContentWidth()
    .frame(maxWidth: .infinity)
    .scrollsOnOverflow()
    .background(Color.tidexBackground.ignoresSafeArea())
    .onChange(of: friendsSaveStatus) { _, status in
      if case .error(let message) = status {
        AccessibilityNotification.Announcement(message).post()
      }
    }
  }

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
    .frame(maxWidth: .infinity)
  }

  private func friendsErrorBanner(message: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.tidexBody)
          .foregroundStyle(Color.tidexError)
          .accessibilityHidden(true)

        Text(message)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button {
        Haptics.play(.light)
        onSelectFriendsOnly()
      } label: {
        Text(.commonRetry)
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexBlueText)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(Spacing.md)
    .background(
      Color.tidexError.opacity(0.1),
      in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

/// One whole-card button: a title, one line about the choice, and an example of what it gives.
private struct PurposeCard<Example: View>: View {
  let title: LocalizedStringResource
  let message: LocalizedStringResource
  let isBusy: Bool
  let action: () -> Void
  @ViewBuilder let example: Example

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
  }

  var body: some View {
    Button {
      Haptics.play(.light)
      action()
    } label: {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        heading

        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.onboardingPostAuthPurposeExample)
            .font(.tidexCaptionRegular)
            .foregroundStyle(Color.tidexTextMuted)

          example
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
      }
      .padding(Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.tidexSurfacePrimary, in: shape)
      .overlay(shape.stroke(Color.tidexBorder, lineWidth: 1))
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    // The example cards hold buttons and texts of their own, so VoiceOver gets one element.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(title))
    .accessibilityHint(Text(message))
    .accessibilityValue(isBusy ? Text(.onboardingSuccessSavingTitle) : Text(verbatim: ""))
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { action() }
  }

  private var heading: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(title)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)

        Text(message)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Group {
        if isBusy {
          ProgressView()
            .tint(.tidexBlue)
        } else {
          Image(systemName: "chevron.right")
            .font(.tidexBodyMedium)
            .foregroundStyle(Color.tidexTextMuted)
        }
      }
      .accessibilityHidden(true)
    }
  }
}

/// A five-hour shift tomorrow at the currency's default hourly wage.
private struct PayExampleCard: View {
  let currency: String

  var body: some View {
    FeaturedShiftCard(
      shift: exampleShift,
      isToday: false,
      isBestShift: false,
      countdownText: nil,
      showFooter: false,
      surfaceStyle: .example
    )
    .userCurrency(currency)
  }

  private var exampleShift: ShiftWithComputations {
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    let hours = 5.0
    let gross = hours * CurrencyConfig.get(currency).wageRangeTier.defaultValue
    let row = ShiftRow(
      id: "purpose-pay-example",
      user_id: "example-user",
      shift_date: tomorrow.toISODateString(),
      start_time: "16:00",
      end_time: "21:00",
      custom_supplements: nil
    )
    let computed = ShiftComputed(
      id: row.id,
      durationHours: hours,
      paidHours: hours,
      basePay: gross,
      supplementPay: 0,
      gross: gross,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    )
    return ShiftWithComputations(shift: row, computed: computed, taxEnabled: false, taxPercentage: 0)
  }
}

/// A friend's shift tomorrow, the way the Friends tab shows it.
private struct FriendExampleCard: View {
  var body: some View {
    FriendCard(
      sharer: SharedUser(
        id: "purpose-friend-example",
        email: "ella@example.com",
        phone: nil,
        firstName: "Ella",
        profilePictureUrl: nil,
        oauthAvatarUrl: nil,
        sharedAt: "2026-01-01",
        showEarnings: false,
        hidden: false
      ),
      preview: SharerShiftPreview(
        sharerId: "purpose-friend-example",
        shift: exampleShift,
        status: .upcoming,
        showEarnings: false,
        currency: nil
      ),
      messagePreview: nil,
      isTyping: false,
      isSelected: false,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {},
      surfaceStyle: .example
    )
  }

  private var exampleShift: SharedShiftData {
    let id = "purpose-friend-example-shift"
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    return SharedShiftData(
      id: id, user_id: id, job_id: nil, job_name: nil, job_color: nil,
      shift_date: tomorrow.toISODateString(),
      start_time: "10:00",
      end_time: "16:00",
      computed: SharedShiftComputed(
        id: id, durationHours: 6, paidHours: 6, basePay: 0, supplementPay: 0, gross: 0,
        breakAudit: SharedBreakAudit(
          method: .none, thresholdHours: 0, deductedHours: 0, source: .none,
          appliedPauseWindows: nil, notes: [])),
      tax_enabled: false, tax_percentage: nil, custom_pause_windows: nil,
      custom_supplements: nil, recurring_id: nil, recurring_anchor_weekday: nil,
      ownerTimeZone: TimeZone.current.identifier)
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
