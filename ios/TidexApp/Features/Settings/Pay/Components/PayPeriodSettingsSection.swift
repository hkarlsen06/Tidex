import SwiftUI

/// Lets the user choose how a job groups worked hours into payouts.
/// Every change is saved through `onUpdate`.
struct PayPeriodSettingsSection: View {
  let jobId: String?
  let payPeriod: PayPeriod
  let payrollDay: Int
  let onUpdate: (PayPeriod) async -> Void

  private enum Kind: Hashable {
    case calendarMonth
    case customMonthly
    case biweekly
  }

  @State private var kind: Kind = .calendarMonth
  @State private var startDay = 16
  @State private var payoutMonthOffset = 0
  @State private var periodEnd = Date()
  @State private var payoutDelayDays = 5

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      labeledPicker(title: .settingsPayPeriodTitle, selection: $kind) {
        Text(.settingsPayPeriodCalendarMonth).tag(Kind.calendarMonth)
        Text(.settingsPayPeriodCustomMonthly).tag(Kind.customMonthly)
        Text(.settingsPayPeriodBiweekly).tag(Kind.biweekly)
      }

      kindOptions

      if let exampleText {
        Text(exampleText)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .onAppear { load(payPeriod) }
    .onChange(of: jobId) { _, _ in load(payPeriod) }
    .onChange(of: draft) { _, newValue in
      guard newValue != payPeriod else { return }
      Task { await onUpdate(newValue) }
    }
    .sensoryFeedback(.selection, trigger: draft) { _, new in new != payPeriod }
  }

  @ViewBuilder private var kindOptions: some View {
    switch kind {
    case .calendarMonth:
      EmptyView()

    case .customMonthly:
      labeledPicker(title: .settingsPayPeriodStartDay, selection: $startDay) {
        ForEach(2...PayPeriod.startDayRange.upperBound, id: \.self) { day in
          Text(.settingsPayPeriodStartDayOption(Self.ordinal(day))).tag(day)
        }
      }
      labeledPicker(title: .settingsPayPeriodPayoutMonth, selection: $payoutMonthOffset) {
        Text(.settingsPayPeriodPayoutSameMonth).tag(0)
        Text(.settingsPayPeriodPayoutNextMonth).tag(1)
      }

    case .biweekly:
      DatePicker(
        String(localized: .settingsPayPeriodLastPeriodEnd),
        selection: $periodEnd,
        displayedComponents: .date
      )
      .font(.tidexLabel)
      .foregroundColor(.tidexTextSecondary)
      DatePicker(
        String(localized: .settingsPayPeriodPayday),
        selection: paydayBinding,
        in: periodEnd...(periodEnd.addingDays(PayPeriod.payoutDelayRange.upperBound)),
        displayedComponents: .date
      )
      .font(.tidexLabel)
      .foregroundColor(.tidexTextSecondary)
    }
  }

  private var draft: PayPeriod {
    switch kind {
    case .calendarMonth:
      return .calendarMonth

    case .customMonthly:
      return .monthly(startDay: startDay, payoutMonthOffset: payoutMonthOffset)

    case .biweekly:
      return .biweekly(anchorEnd: periodEnd.toISODateString(), payoutDelayDays: payoutDelayDays)
    }
  }

  private var paydayBinding: Binding<Date> {
    Binding(
      get: { periodEnd.addingDays(payoutDelayDays) },
      set: { newValue in
        let days =
          PayPeriodCalendar.daysBetween(periodEnd.toISODateString(), newValue.toISODateString())
          ?? payoutDelayDays
        payoutDelayDays = min(max(days, 0), PayPeriod.payoutDelayRange.upperBound)
      }
    )
  }

  /// "Work from 16 Aug to 15 Sep is paid on 25 Sep." for the period containing today.
  private var exampleText: String? {
    let schedule = PayoutSchedule(period: draft, payrollDay: payrollDay)
    guard let window = schedule.window(containing: Date().toISODateString()),
      let start = Date.fromISODateString(window.start),
      let end = Date.fromISODateString(window.end)
    else {
      return nil
    }
    let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
    return String(
      localized: .settingsPayPeriodExample(
        start.formatted(format), end.formatted(format), window.adjustedPayoutDate.formatted(format)))
  }

  /// Sets the controls from the saved value. Options that are not selected keep sensible
  /// defaults (the 16th, a period ending last Sunday paid that Friday) for when the user switches.
  private func load(_ period: PayPeriod) {
    startDay = 16
    payoutMonthOffset = 0
    periodEnd = Self.mostRecentSunday()
    payoutDelayDays = 5

    switch period {
    case .monthly(let day, let offset):
      kind = day == 1 ? .calendarMonth : .customMonthly
      if day != 1 {
        startDay = day
        payoutMonthOffset = offset
      }

    case .biweekly(let anchorEnd, let delay):
      kind = .biweekly
      periodEnd = Date.fromISODateString(anchorEnd) ?? periodEnd
      payoutDelayDays = delay
    }
  }

  private static func mostRecentSunday(from date: Date = Date()) -> Date {
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: date)  // 1 = Sunday
    return calendar.startOfDay(for: date).addingDays(-(weekday - 1))
  }

  private static func ordinal(_ day: Int) -> String {
    guard !Locale.current.isNorwegian else { return "\(day)" }
    switch day % 100 {
    case 11, 12, 13:
      return "\(day)th"

    default:
      let suffixes = [1: "st", 2: "nd", 3: "rd"]
      return "\(day)\(suffixes[day % 10] ?? "th")"
    }
  }

  private func labeledPicker<Value: Hashable, Content: View>(
    title: LocalizedStringResource,
    selection: Binding<Value>,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(title)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Picker(String(localized: title), selection: selection, content: content)
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(.tidexBlue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
  }
}

extension Date {
  fileprivate func addingDays(_ days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
  }
}
