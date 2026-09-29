import SwiftUI

/// A date-based entry point to the saved inputs behind a pay estimate.
struct PaySettingsReviewCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var isExpanded: Bool
  @Binding var workDate: Date
  let snapshots: [WageSnapshot]
  let currency: String
  let payrollDay: Int
  let halfTaxMonth: Int?
  var payPeriod: PayPeriod = .calendarMonth
  let onEdit: (WageSnapshot, WageSnapshotEditorSection) -> Void

  private var context: PaySettingsContext {
    PaySettingsContext(
      workDate: workDate, snapshots: snapshots, payrollDay: payrollDay, halfTaxMonth: halfTaxMonth,
      payPeriod: payPeriod
    )
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      reviewContent
        .padding(.top, Spacing.sm)
    } label: {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(.settingsPayReviewTitle)
          .font(.tidexBodyMedium)
          .accessibilityAddTraits(.isHeader)
        // The date picker row shows the date once the card is open.
        if !isExpanded {
          Text(
            .settingsPayReviewActiveOn(
              workDate.formatted(.dateTime.day().month(.wide).year().calendar(.gregorian))))
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
        }
      }
      .multilineTextAlignment(.leading)
      .frame(minHeight: 44, alignment: .leading)
    }
    .tint(Color.tidexTextSecondary)
    .accessibilityIdentifier("pay-settings.review-disclosure")
    .padding(Spacing.md)
    .background(
      Color.tidexSurfacePrimary,
      in: RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
    )
    .foregroundStyle(Color.tidexTextPrimary)
    .fixedSize(horizontal: false, vertical: true)
  }

  /// One line per setting: what it is on the left, the value on the right.
  private var reviewContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(.settingsPayReviewWorkDate)
            workDatePicker.labelsHidden()
          }
        } else {
          workDatePicker
        }
      }
      .padding(.bottom, Spacing.xs)

      if let snapshot = context.wageSnapshot {
        wageRows(snapshot)
      }

      if let snapshot = context.taxSnapshot {
        Divider()
        row(
          .settingsPayEditorTaxTitle, value: taxSummary(snapshot),
          subtitle: String(localized: .settingsPayReviewTaxPayday(formattedDate(context.taxDate))),
          snapshot: snapshot, section: .tax)
          .accessibilityIdentifier("pay-settings.review-tax")
      }

      if context.wageSnapshot == nil || context.taxSnapshot == nil {
        Text(.settingsPayReviewMissingSettings)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexWarning)
          .padding(.top, Spacing.sm)
      }
    }
  }

  @ViewBuilder
  private func wageRows(_ snapshot: WageSnapshot) -> some View {
    Divider()
    row(
      .settingsPayReviewHourlyWage, value: hourlyAmount(snapshot.hourly_wage),
      snapshot: snapshot, section: .wage)
    Divider()
    row(
      .settingsPayEditorSupplementsTitle,
      value: String(localized: .settingsPayReviewRules(snapshot.supplements.rules.count)),
      snapshot: snapshot, section: .supplements)
    Divider()
    row(
      .settingsPayEditorBreakTitle, value: breakSummary(snapshot),
      snapshot: snapshot, section: .breaks)
    Divider()
    row(
      .settingsPayEditorOvertimeTitle, value: overtimeSummary(snapshot),
      snapshot: snapshot, section: .overtime)
  }

  private var workDatePicker: some View {
    DatePicker(selection: $workDate, displayedComponents: .date) {
      Text(.settingsPayReviewWorkDate)
    }
    .font(.tidexSubheadline)
    .datePickerStyle(.compact)
    .accessibilityIdentifier("pay-settings.work-date")
  }

  private func row(
    _ title: LocalizedStringResource, value: String, subtitle: String? = nil,
    snapshot: WageSnapshot, section: WageSnapshotEditorSection
  ) -> some View {
    Button {
      onEdit(snapshot, section)
    } label: {
      HStack(spacing: Spacing.sm) {
        rowText(title, value: value, subtitle: subtitle)
        Image(systemName: "chevron.right")
          .font(.tidexCaption)
          .foregroundStyle(Color.tidexTextMuted)
          .accessibilityHidden(true)
      }
      .frame(minHeight: 44)
      .padding(.vertical, Spacing.xxs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func rowText(
    _ title: LocalizedStringResource, value: String, subtitle: String?
  ) -> some View {
    let label = VStack(alignment: .leading, spacing: Spacing.micro) {
      Text(title)
        .font(.tidexBody)
      if let subtitle {
        Text(subtitle)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
    }
    let valueText = Text(value)
      .font(.tidexBody)
      .foregroundStyle(Color.tidexTextSecondary)
      .monospacedDigit()

    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        label
        valueText
      }
      Spacer(minLength: 0)
    } else {
      label
      Spacer(minLength: Spacing.sm)
      valueText
        .multilineTextAlignment(.trailing)
    }
  }

  private func breakSummary(_ snapshot: WageSnapshot) -> String {
    guard snapshot.effectiveBreakEnabled, snapshot.breakMethod != .none else {
      return String(localized: .settingsPayReviewOff)
    }
    return String(
      localized: .settingsPayReviewBreakShort(
        duration(Double(snapshot.effectiveBreakDeductionMinutes), unit: .minutes),
        duration(snapshot.effectiveBreakThresholdHours, unit: .hours)
      ))
  }

  private func overtimeSummary(_ snapshot: WageSnapshot) -> String {
    guard let overtime = snapshot.overtime.runtimeEnabledConfig else {
      return String(localized: .settingsPayReviewOff)
    }
    return String(
      localized: .settingsPayReviewOvertimeShort(
        duration(overtime.weeklyThresholdHours, unit: .hours)))
  }

  private func taxSummary(_ snapshot: WageSnapshot) -> String {
    guard snapshot.effectiveTaxEnabled else {
      return String(localized: .settingsPayReviewOff)
    }
    let rate = (context.effectiveTaxPercentage / 100).formatted(
      .percent.precision(.fractionLength(0...2)).locale(.appLocale))
    return context.appliesHalfTax ? String(localized: .settingsPayReviewTaxRateHalf(rate)) : rate
  }

  /// "30 min", "5,5 t": abbreviated units in the app locale.
  private func duration(_ value: Double, unit: UnitDuration) -> String {
    Measurement(value: value, unit: unit).formatted(
      .measurement(
        width: .abbreviated, usage: .asProvided,
        numberFormatStyle: .number.precision(.fractionLength(0...2))
      )
      .locale(.appLocale))
  }

  private func hourlyAmount(_ amount: Double) -> String {
    let number = CurrencyConfig.formatPlain(amount, includeDecimals: true)
    let config = CurrencyConfig.get(currency)
    let money = config.display == .prefix ? "\(currency)\(number)" : "\(number) \(currency)"
    return "\(money)\(String(localized: .commonPerHourShort))"
  }

  private func formattedDate(_ isoDate: String) -> String {
    Date.fromISODateString(isoDate)?.formatted(.dateTime.day().month(.wide).year().calendar(.gregorian))
      ?? isoDate
  }
}
