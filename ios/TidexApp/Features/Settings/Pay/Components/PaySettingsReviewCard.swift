import SwiftUI

/// A date-based entry point to the saved inputs behind a pay estimate.
struct PaySettingsReviewCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var isExpanded: Bool
  @Binding var workDate: Date
  let snapshots: [WageSnapshot]
  let entries: [WageTimelineEntry]
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
        .padding(.top, Spacing.md)

      Text(.settingsPayReviewDateExplanation)
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextSecondary)
        .padding(.top, Spacing.sm)
    } label: {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(.settingsPayReviewTitle)
          .font(.tidexTitle2)
          .accessibilityAddTraits(.isHeader)
        Text(.settingsPayReviewActiveOn(workDate.formatted(.dateTime.day().month(.wide).year())))
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
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

  private var reviewContent: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text(.settingsPayReviewWorkDate)
          workDatePicker.labelsHidden()
        }
      } else {
        workDatePicker
      }

      Divider()

      if let snapshot = context.wageSnapshot {
        VStack(alignment: .leading, spacing: 0) {
          Text(periodLabel(for: snapshot))
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
            .padding(.bottom, Spacing.xs)

          row(
            .settingsPayReviewHourlyWage, value: hourlyAmount(snapshot.hourly_wage),
            snapshot: snapshot, section: .wage)
          Divider()
          row(
            .settingsPayEditorSupplementsTitle,
            value: String(
              localized: .settingsPayReviewRuleCount(Int32(snapshot.supplements.rules.count))
            ), snapshot: snapshot, section: .supplements)
          Divider()
          row(
            .settingsPayEditorBreakTitle, value: breakSummary(snapshot),
            snapshot: snapshot, section: .breaks)
          Divider()
          row(
            .settingsPayEditorOvertimeTitle, value: overtimeSummary(snapshot),
            snapshot: snapshot, section: .overtime)
        }
      } else {
        Text(.settingsPayReviewMissingSettings)
          .foregroundStyle(Color.tidexWarning)
      }

      Divider()

      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(.settingsPayReviewTaxDate(formattedDate(context.taxDate)))
          .font(.tidexLabelStrong)
          .accessibilityAddTraits(.isHeader)

        if let snapshot = context.taxSnapshot {
          Text(periodLabel(for: snapshot))
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)

          Text(
            snapshot.effectiveTaxEnabled
              ? String(
                localized: .settingsPayReviewTaxRate(
                  FormatterCache.percentagePoints(context.effectiveTaxPercentage, fractionDigits: 2)
                ))
              : String(localized: .settingsPayReviewTaxOff)
          )
          .font(.tidexBodyMedium)

          if snapshot.effectiveTaxEnabled, context.appliesHalfTax {
            Text(.settingsPayReviewHalfTax)
              .font(.tidexFootnote)
              .foregroundStyle(Color.tidexTextSecondary)
          }

          editButton(snapshot, section: .tax, title: .settingsPayReviewEditTaxSettings)
        } else {
          Text(.settingsPayReviewMissingSettings)
            .foregroundStyle(Color.tidexWarning)
        }
      }
    }
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
    _ title: LocalizedStringResource, value: String,
    snapshot: WageSnapshot, section: WageSnapshotEditorSection
  ) -> some View {
    Button {
      onEdit(snapshot, section)
    } label: {
      HStack(spacing: Spacing.sm) {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(title)
            .font(.tidexLabel)
          Text(value)
            .font(section == .wage ? .tidexTitle : .tidexSubheadline)
            .foregroundStyle(section == .wage ? Color.tidexTextPrimary : .tidexTextSecondary)
            .monospacedDigit()
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.tidexCaption)
          .foregroundStyle(Color.tidexTextMuted)
          .accessibilityHidden(true)
      }
      .frame(minHeight: 44, alignment: .leading)
      .padding(.vertical, Spacing.xs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
  }

  private func editButton(
    _ snapshot: WageSnapshot, section: WageSnapshotEditorSection, title: LocalizedStringResource
  ) -> some View {
    Button {
      onEdit(snapshot, section)
    } label: {
      Label(title, systemImage: "slider.horizontal.3")
        .font(.tidexLabel)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color.tidexBlue)
  }

  private func periodLabel(for snapshot: WageSnapshot) -> String {
    entries.first { $0.id == snapshot.id }?.dateRange
      ?? String(localized: .settingsPayPeriodAllDates)
  }

  private func breakSummary(_ snapshot: WageSnapshot) -> String {
    guard snapshot.effectiveBreakEnabled, snapshot.breakMethod != .none else {
      return String(localized: .settingsPayReviewBreakOff)
    }
    return String(
      localized: .settingsPayReviewBreakSummary(
        String(localized: .settingsPayBreakMinutes(Int32(snapshot.effectiveBreakDeductionMinutes))),
        String(
          localized: .settingsPayBreakHoursDecimal(
            snapshot.effectiveBreakThresholdHours.formatted(.number.locale(.appLocale))))
      ))
  }

  private func overtimeSummary(_ snapshot: WageSnapshot) -> String {
    guard let overtime = snapshot.overtime.runtimeEnabledConfig else {
      return String(localized: .settingsPayReviewOvertimeOff)
    }
    return String(
      localized: .settingsPayReviewOvertimeSummary(
        overtime.weeklyThresholdHours.formatted(.number.locale(.appLocale))))
  }

  private func hourlyAmount(_ amount: Double) -> String {
    let number = CurrencyConfig.formatPlain(amount, includeDecimals: true)
    let config = CurrencyConfig.get(currency)
    let money = config.display == .prefix ? "\(currency)\(number)" : "\(number) \(currency)"
    return "\(money)\(String(localized: .commonPerHourShort))"
  }

  private func formattedDate(_ isoDate: String) -> String {
    Date.fromISODateString(isoDate)?.formatted(.dateTime.day().month(.wide).year()) ?? isoDate
  }
}
