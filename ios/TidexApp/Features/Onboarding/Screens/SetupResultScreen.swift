import SwiftUI

/// Last setup step. It shows the save, then either the demo shift carried over from before
/// sign-up with what it pays, or the ways to add a first shift.
struct SetupResultScreen: View {
  let status: OnboardingSaveManager.SaveStatus
  /// Set once setup is saved, when the user built a shift in the pre-auth demo.
  let carriedShiftPay: CarriedShiftPay?
  let carriedShiftStatus: OnboardingSaveManager.SaveStatus
  /// The break, tax and payday the saved job uses, which setup no longer asks about.
  let payAssumptions: PayAssumptions?
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
      CarriedShiftOverview(pay: pay)
      settingsNote
      if case .error(let message) = carriedShiftStatus {
        errorBanner(message: message)
      }

    case .ready:
      settingsNote

    case .saving:
      EmptyView()
    }
  }

  /// The settings setup chose without asking, and that they can be changed.
  private var settingsNote: some View {
    VStack(spacing: Spacing.xxs) {
      if let payAssumptions {
        Text(verbatim: payAssumptions.summary)
      }
      Text(.onboardingSuccessReassurance)
    }
    .font(.tidexFootnote)
    .foregroundStyle(Color.tidexTextMuted)
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
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

/// The carried shift on the demo's calendar, each day with its pay, then the pay worked out.
private struct CarriedShiftOverview: View {
  let pay: CarriedShiftPay

  private var dates: [Date] {
    pay.shift.dates.compactMap { Date.fromISODateString($0) }.sorted()
  }

  /// "November 2026", or "November – desember 2026" when the dates cross a month.
  private var monthsTitle: String {
    let style = Date.FormatStyle.dateTime.month(.wide).calendar(.gregorian).locale(.appLocale)
    guard let first = dates.first, let last = dates.last else { return "" }
    let year = last.formatted(.dateTime.year().calendar(.gregorian).locale(.appLocale))
    let firstMonth = first.formatted(style)
    let lastMonth = last.formatted(style)
    let months = firstMonth == lastMonth ? firstMonth : "\(firstMonth) – \(lastMonth)"
    return "\(months) \(year)".sentenceCased()
  }

  var body: some View {
    VStack(spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(verbatim: monthsTitle)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)
          .padding(.horizontal, Spacing.xs)

        AddShiftCalendarView(
          viewModel: CarriedShiftCalendar(
            dates: Set(pay.shift.dates),
            earnings: pay.dailyGross.mapValues {
              CalendarEarningsData(net: $0, gross: $0, hasTaxEnabled: false)
            }
          ),
          onlyWeeksOf: Set(pay.shift.dates)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      payLines
    }
  }

  private var payLines: some View {
    VStack(spacing: Spacing.xxs) {
      VStack(spacing: 2) {
        line(label: String(localized: .shiftsBasePay), amount: pay.basePay)
        Text(verbatim: "\(timeText) · \(baseDetail)")
          .font(.tidexFootnote)
          .monospacedDigit()
          .foregroundStyle(Color.tidexTextMuted)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityElement(children: .combine)

      if pay.supplementPay > 0 {
        line(label: String(localized: .shiftsTotalSupplement), amount: pay.supplementPay)
      }
      if pay.breakDeduction > 0 {
        line(label: String(localized: .shiftsBreakDeduction), amount: -pay.breakDeduction)
      }

      HStack(alignment: .firstTextBaseline) {
        Text(.shiftsGrossPay)
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexTextPrimary)
        Spacer(minLength: Spacing.sm)
        Text(verbatim: format(pay.gross))
          .font(.tidexAmountMedium)
          .monospacedDigit()
          .foregroundStyle(Color.tidexTextPrimary)
      }
      .padding(.top, Spacing.xs)
      .accessibilityElement(children: .combine)
    }
  }

  private func line(label: String, amount: Double) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
      Text(verbatim: label)
        .foregroundStyle(Color.tidexTextSecondary)
      Spacer(minLength: 0)
      Text(verbatim: amount < 0 ? "\u{2212}\(format(-amount))" : format(amount))
        .monospacedDigit()
        .foregroundStyle(Color.tidexTextPrimary)
    }
    .font(.tidexSubheadline)
    .accessibilityElement(children: .combine)
  }

  private func format(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: pay.currency)
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

/// Feeds the Add screen's calendar with the carried dates. Taps do nothing.
@Observable
private final class CarriedShiftCalendar: AddShiftCalendarViewModeling {
  let displayMonth = Date()
  let selectedDates: Set<String>
  let previewEarnings: [String: CalendarEarningsData]
  let conflictDates: Set<String> = []
  let existingShiftHours: [String: HoursData] = [:]
  let navigationDirection: MonthNavigationDirection? = nil

  init(dates: Set<String>, earnings: [String: CalendarEarningsData]) {
    selectedDates = dates
    previewEarnings = earnings
  }

  func toggleDate(_ dateISO: String) {}
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
      payAssumptions: nil,
      onRetry: {}, onBack: {}, onSaveCarriedShift: {}, onDeclineCarriedShift: {},
      onAddFirstShift: {}, onFinish: {}
    )
  }
#endif
