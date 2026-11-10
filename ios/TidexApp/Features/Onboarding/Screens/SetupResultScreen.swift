import SwiftUI

/// Last setup step. It shows the save, then either the demo shift carried over from before
/// sign-up with what it pays, or the ways to add a first shift.
struct SetupResultScreen: View {
  let status: OnboardingSaveManager.SaveStatus
  /// Set once setup is saved, when the user built a shift in the pre-auth demo.
  let carriedShiftPay: CarriedShiftPay?
  let carriedShiftStatus: OnboardingSaveManager.SaveStatus
  let onRetry: () -> Void
  /// Returns to the wage step with the input kept.
  let onBack: () -> Void
  let onSaveCarriedShift: () -> Void
  let onDeclineCarriedShift: () -> Void
  let onAddFirstShift: () -> Void
  let onFinish: () -> Void

  @State private var showCalendarImport = false
  @State private var didImportFromCalendar = false
  @ScaledMetric(relativeTo: .largeTitle) private var scaledIconSize: CGFloat = 64

  private enum Phase: Equatable {
    case saving
    case failed(message: String)
    case carriedShift(CarriedShiftPay)
    case ready
  }

  private var phase: Phase {
    switch status {
    case .idle, .saving:
      return .saving
    case .error(let message):
      return .failed(message: message)
    case .success:
      return carriedShiftPay.map(Phase.carriedShift) ?? .ready
    }
  }

  /// The status icon grows with text, up to a size that still leaves room for the message.
  private var iconSize: CGFloat {
    min(scaledIconSize, 96)  // swiftlint:disable:this no_magic_numbers
  }

  var body: some View {
    VStack(spacing: Spacing.lg) {
      Spacer(minLength: Spacing.md)

      content

      Spacer(minLength: Spacing.md)

      actions
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, Spacing.xl)
    .adaptiveContentWidth()
    .frame(maxWidth: .infinity)
    .scrollsOnOverflow()
    .background(Color.tidexBackground.ignoresSafeArea())
    .sensoryFeedback(.success, trigger: status) { _, newValue in newValue == .success }
    .sensoryFeedback(.error, trigger: status) { _, newValue in
      if case .error = newValue { return true }
      return false
    }
    .onChange(of: status) { _, _ in
      // The status changes without moving VoiceOver focus, so read the new title aloud.
      AccessibilityNotification.Announcement(String(localized: title)).post()
    }
    .sheet(
      isPresented: $showCalendarImport,
      onDismiss: {
        // Shifts are in, so finish setup and show them in the app.
        if didImportFromCalendar {
          onFinish()
        }
      }
    ) {
      CalendarImportView { _ in
        didImportFromCalendar = true
      }
    }
  }

  // MARK: - Content

  private var content: some View {
    VStack(spacing: Spacing.lg) {
      if let statusIcon {
        statusIcon
      }

      VStack(spacing: Spacing.sm) {
        Text(title)
          .font(.tidexScreenTitle)
          .foregroundStyle(Color.tidexTextPrimary)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        Text(subtitle)
          .font(.tidexBody)
          .foregroundStyle(Color.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)

      detail
    }
  }

  @ViewBuilder
  private var detail: some View {
    switch phase {
    case .failed(let message):
      errorBanner(message: message)

    case .carriedShift(let pay):
      CarriedShiftPayCard(pay: pay)
      if case .error(let message) = carriedShiftStatus {
        errorBanner(message: message)
      }

    case .ready:
      Text(.onboardingSuccessReassurance)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextMuted)
        .multilineTextAlignment(.center)

    case .saving:
      EmptyView()
    }
  }

  private var statusIcon: AnyView? {
    switch phase {
    case .saving:
      return AnyView(
        ProgressView()
          .controlSize(.large)
          .tint(.tidexBlue)
          .frame(width: iconSize, height: iconSize)
          .accessibilityHidden(true))

    case .failed:
      return AnyView(icon("exclamationmark.circle.fill", color: .tidexError))

    case .ready:
      return AnyView(icon("checkmark.circle.fill", color: .tidexSuccess))

    case .carriedShift:
      return nil
    }
  }

  private func icon(_ systemName: String, color: Color) -> some View {
    Image(systemName: systemName)
      .font(.system(size: iconSize))
      .foregroundStyle(color)
      .accessibilityHidden(true)
  }

  private var title: LocalizedStringResource {
    switch phase {
    case .saving:
      return .onboardingSuccessSavingTitle
    case .failed:
      return .onboardingSuccessErrorTitle
    case .carriedShift(let pay):
      return pay.shift.dates.count > 1
        ? .onboardingSuccessCarriedShiftsTitle : .onboardingSuccessCarriedShiftTitle
    case .ready:
      return .onboardingSuccessTitle
    }
  }

  private var subtitle: LocalizedStringResource {
    switch phase {
    case .saving:
      return .onboardingSuccessSaving
    case .failed:
      return .onboardingSuccessErrorSubtitle
    case .carriedShift:
      return .onboardingSuccessCarriedShiftSubtitle
    case .ready:
      return .onboardingSuccessSubtitle
    }
  }

  // MARK: - Actions

  @ViewBuilder
  private var actions: some View {
    VStack(spacing: Spacing.xs) {
      switch phase {
      case .saving:
        OnboardingButton(
          title: String(localized: .onboardingSuccessSavingTitle), isEnabled: false, action: {})

      case .failed:
        OnboardingButton(title: String(localized: .commonRetry), action: onRetry)
        OnboardingButton(title: String(localized: .commonBack), action: onBack, style: .secondary)

      case .carriedShift(let pay):
        carriedShiftActions(for: pay)

      case .ready:
        readyActions
      }
    }
  }

  @ViewBuilder
  private func carriedShiftActions(for pay: CarriedShiftPay) -> some View {
    let isSaving = carriedShiftStatus == .saving
    OnboardingButton(
      title: String(localized: saveShiftTitle(for: pay, isSaving: isSaving)),
      isEnabled: !isSaving,
      action: onSaveCarriedShift
    )
    OnboardingButton(
      title: String(localized: .onboardingSuccessNotNow),
      isEnabled: !isSaving,
      action: onDeclineCarriedShift,
      style: .secondary
    )
  }

  @ViewBuilder
  private var readyActions: some View {
    OnboardingButton(
      title: String(localized: .onboardingSuccessAddFirstShift), action: onAddFirstShift)
    OnboardingButton(
      title: String(localized: .calendarImportEntryButton),
      action: { showCalendarImport = true },
      style: .secondary
    )
    Button {
      Haptics.play(.light)
      onFinish()
    } label: {
      Text(.onboardingSuccessButton)
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func saveShiftTitle(for pay: CarriedShiftPay, isSaving: Bool) -> LocalizedStringResource {
    if isSaving {
      return .onboardingSuccessSavingShift
    }
    return pay.shift.dates.count > 1
      ? .onboardingSuccessSaveCarriedShifts : .onboardingSuccessSaveCarriedShift
  }

  private func errorBanner(message: String) -> some View {
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
    .padding(Spacing.md)
    .background(
      Color.tidexError.opacity(0.1),
      in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
    )
    .announcesToVoiceOver(message)
  }
}

/// The carried shift's dates and times, and what they pay, in the rows the shift details use.
private struct CarriedShiftPayCard: View {
  let pay: CarriedShiftPay

  var body: some View {
    EarningsBreakdownCard {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(datesText)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)
          .fixedSize(horizontal: false, vertical: true)

        Text(timeText)
          .font(.tidexSubheadline)
          .monospacedDigit()
          .foregroundStyle(Color.tidexTextSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)

      Divider()
      payRows
      Divider()

      EarningsBreakdownCard<EmptyView>.Row(
        label: String(localized: .shiftsGrossPay), value: format(pay.gross), isHighlighted: true)
    }
  }

  @ViewBuilder
  private var payRows: some View {
    VStack(alignment: .leading, spacing: 2) {
      EarningsBreakdownCard<EmptyView>.Row(
        label: String(localized: .shiftsBasePay), value: format(pay.basePay))
      Text(baseDetail)
        .font(.tidexFootnote)
        .monospacedDigit()
        .foregroundStyle(Color.tidexTextMuted)
    }
    .accessibilityElement(children: .combine)

    if pay.supplementPay > 0 {
      EarningsBreakdownCard<EmptyView>.Row(
        label: String(localized: .shiftsTotalSupplement), value: format(pay.supplementPay))
    }

    if pay.breakDeduction > 0 {
      EarningsBreakdownCard<EmptyView>.Row(
        label: String(localized: .shiftsBreakDeduction),
        value: "−\(format(pay.breakDeduction))",
        valueColor: .tidexError
      )
    }
  }

  private func format(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: pay.currency)
  }

  private var datesText: String {
    let dates = pay.shift.dates.compactMap { Date.fromISODateString($0) }
    if dates.count == 1, let date = dates.first {
      return date.formatted(
        .dateTime.weekday(.wide).day().month(.wide).calendar(.gregorian).locale(.appLocale)
      ).sentenceCased()
    }
    return dates.map {
      $0.formatted(
        .dateTime.weekday(.abbreviated).day().month(.abbreviated).calendar(.gregorian)
          .locale(.appLocale))
    }
    .formatted(.list(type: .and).locale(.appLocale))
    .sentenceCased()
  }

  private var timeText: String {
    ShiftCardFormatter.localizedTimeRange(
      start: pay.shift.startTime, end: pay.shift.endTime, locale: .appLocale)
  }

  /// Hours times the hourly base rate, so the base pay can be checked by hand.
  private var baseDetail: String {
    let hours = Measurement(value: pay.workedHours, unit: UnitDuration.hours).formatted(
      .measurement(
        width: .abbreviated, usage: .asProvided,
        numberFormatStyle: .number.precision(.fractionLength(0...2))
      ).locale(.appLocale))
    let rate = pay.workedHours > 0 ? pay.basePay / pay.workedHours : 0
    // A rate such as 213,50 keeps its øre, so the line still adds up.
    let rateText = CurrencyConfig.format(
      rate, currency: pay.currency, includeDecimals: rate != rate.rounded())
    return "\(hours) × \(rateText)"
  }
}

#if DEBUG
  #Preview("Carried shift") {
    SetupResultScreen(
      status: .success,
      carriedShiftPay: CarriedShiftPay(
        shift: CarriedDemoShift(dates: ["2026-11-12"], startTime: "16:00", endTime: "21:00"),
        snapshots: [],
        currency: "kr"
      ),
      carriedShiftStatus: .idle,
      onRetry: {}, onBack: {}, onSaveCarriedShift: {}, onDeclineCarriedShift: {},
      onAddFirstShift: {}, onFinish: {}
    )
  }
#endif
