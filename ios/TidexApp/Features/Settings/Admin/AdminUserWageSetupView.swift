import SwiftUI

/// Read-only Wage setup sections for the user detail screen: one section per job with its
/// current wage, older wages, and the user's payroll adjustments.
struct AdminUserWageSetupSections: View {
  let setup: AdminWageSetup

  var body: some View {
    if setup.jobs.isEmpty {
      Section("Wage setup") {
        Text("No jobs or wages set up.")
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
    }

    ForEach(setup.jobs) { job in
      AdminJobWageSection(
        job: job, snapshots: setup.snapshots(for: job), settings: setup.settings)
    }

    if !setup.adjustments.isEmpty {
      Section("Payroll adjustments") {
        ForEach(setup.adjustments) { adjustment in
          LabeledContent {
            Text(
              CurrencyConfig.format(
                adjustment.amount, currency: adjustment.currency, includeDecimals: true))
          } label: {
            Text(adjustment.description)
            Text(
              [
                adjustment.category.rawValue.adminHumanized,
                adminDay(adjustment.payout_date).map {
                  "paid \($0.formatted(.dateTime.day().month().year()))"
                },
              ]
              .compactMap { $0 }
              .joined(separator: " · ")
            )
          }
        }
      }
    }
  }
}

private struct AdminJobWageSection: View {
  let job: Job
  let snapshots: [WageSnapshot]
  let settings: AdminWageSetup.Settings?

  /// The newest snapshot that has started, or the oldest if all of them start later.
  private var current: WageSnapshot? {
    let today: String = Date().toISODateString()
    return snapshots.last { ($0.from_date ?? "") <= today } ?? snapshots.first
  }

  private var currency: String { job.currency }
  private var payrollDay: Int? { job.payroll_day ?? settings?.payrollDay }
  private var monthlyGoal: Int? { job.monthly_goal ?? settings?.monthlyGoal }
  private var halfTaxMonth: Int? { job.half_tax_month ?? settings?.halfTaxMonth }

  var body: some View {
    Section {
      payRows
      wageRows
    } header: {
      HStack(spacing: Spacing.xs) {
        Text("Wage setup")
        WorkplaceNameText(name: job.name, colorHex: job.color, font: .tidexFootnote)
        if job.is_default {
          Text("Default")
        }
      }
    }
  }

  @ViewBuilder private var payRows: some View {
    LabeledContent("Pay period", value: payPeriodText)
    if !(job.pay_period?.isBiweekly ?? false) {
      LabeledContent("Payday", value: payrollDay.map { "Day \($0)" } ?? "Not set")
    }
    LabeledContent("Monthly goal") {
      if let monthlyGoal {
        Text(CurrencyConfig.format(Double(monthlyGoal), currency: currency))
      } else {
        Text("None")
      }
    }
    LabeledContent("Half tax month", value: halfTaxMonth.map(monthName) ?? "Off")
  }

  @ViewBuilder private var wageRows: some View {
    if let current {
      if snapshots.count > 1 {
        LabeledContent("Current wage", value: Self.startText(current))
      }
      AdminWageSnapshotRows(snapshot: current, currency: currency)
      let others: [WageSnapshot] = snapshots.filter { $0.id != current.id }.reversed()
      if !others.isEmpty {
        Text("Wage history")
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
        ForEach(others) { snapshot in
          DisclosureGroup {
            AdminWageSnapshotRows(snapshot: snapshot, currency: currency)
          } label: {
            LabeledContent(
              Self.startText(snapshot),
              value: CurrencyConfig.format(
                snapshot.hourly_wage, currency: currency, includeDecimals: true))
          }
        }
      }
    } else {
      Text("No wage set up for this job.")
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextSecondary)
    }
  }

  private var payPeriodText: String {
    switch job.pay_period ?? .calendarMonth {
    case .calendarMonth:
      "Calendar month, paid the month after"
    case .monthly(let startDay, let payoutMonthOffset):
      "Monthly from day \(startDay), paid \(payoutMonthOffset == 0 ? "the same month" : "the month after")"
    case .biweekly(let anchorEnd, let payoutDelayDays):
      "Every 2 weeks, one ends \(anchorEnd), paid \(payoutDelayDays) days later"
    }
  }

  private func monthName(_ month: Int) -> String {
    Calendar.current.monthSymbols[(month - 1) % 12]
  }

  static func startText(_ snapshot: WageSnapshot) -> String {
    guard let date = adminDay(snapshot.from_date) else { return "From the start" }
    return "From \(date.formatted(.dateTime.day().month().year()))"
  }
}

/// Wage, tax, break, overtime and supplements for one wage snapshot.
private struct AdminWageSnapshotRows: View {
  let snapshot: WageSnapshot
  let currency: String

  var body: some View {
    LabeledContent(
      "Hourly wage",
      value: CurrencyConfig.format(snapshot.hourly_wage, currency: currency, includeDecimals: true))
    LabeledContent("Wage source", value: wageSourceText)
    LabeledContent("Tax", value: taxText)
    LabeledContent("Break", value: breakText)
    LabeledContent("Overtime", value: overtimeText)
    if snapshot.overtime.enabled {
      ForEach(Array(snapshot.overtime.rules.enumerated()), id: \.offset) { _, rule in
        ruleRow(
          days: OnboardingSupplementRule(days: Set(rule.days)).spokenDaysDescription
            + (rule.appliesOnHolidays ? ", holidays" : ""),
          time: "\(rule.from) - \(rule.to)",
          value: "+\(rule.percent.formatted(.number.precision(.fractionLength(0...2))))%")
      }
    }

    if snapshot.effectiveSupplements.isEmpty {
      LabeledContent("Supplements", value: "None")
    } else {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text("Supplements")
        Grid(alignment: .leading, horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.xxs) {
          ForEach(Array(snapshot.effectiveSupplements.enumerated()), id: \.offset) { _, rule in
            let display: OnboardingSupplementRule = OnboardingSupplementRule(from: rule)
            GridRow {
              Text(display.spokenDaysDescription)
              Text(display.timeDescription).monospacedDigit()
              Text(display.valueDescription(locale: .appLocale, currency: currency))
                .gridColumnAlignment(.trailing)
                .foregroundStyle(Color.tidexBlueText)
            }
            .font(.tidexFootnote)
          }
        }
        .foregroundStyle(Color.tidexTextSecondary)
      }
    }
  }

  private func ruleRow(days: String, time: String, value: String) -> some View {
    LabeledContent {
      Text(value)
    } label: {
      Text(days)
      Text(time)
    }
  }

  private var wageSourceText: String {
    guard let tariff = snapshot.tariff_type_id else { return "Custom wage" }
    return snapshot.wage_level.map { "\(tariff), level \($0)" } ?? tariff
  }

  private var taxText: String {
    guard snapshot.effectiveTaxEnabled else { return "Off" }
    return
      "\(snapshot.effectiveTaxPercentage.formatted(.number.precision(.fractionLength(0...2))))%"
  }

  private var breakText: String {
    guard snapshot.effectiveBreakEnabled, snapshot.breakMethod != .none else { return "Off" }
    let hours: String = snapshot.effectiveBreakThresholdHours.formatted(
      .number.precision(.fractionLength(0...2)))
    let method: String =
      switch snapshot.breakMethod {
      case .proportional: "proportional"
      case .baseOnly: "from base pay first"
      case .endOfShift: "from end of shift"
      case .none: "none"
      }
    return "\(snapshot.effectiveBreakDeductionMinutes) min over \(hours) h, \(method)"
  }

  private var overtimeText: String {
    guard snapshot.overtime.enabled else { return "Off" }
    let hours: String = snapshot.overtime.weeklyThresholdHours.formatted(
      .number.precision(.fractionLength(0...2)))
    return "Over \(hours) h a week"
  }
}
