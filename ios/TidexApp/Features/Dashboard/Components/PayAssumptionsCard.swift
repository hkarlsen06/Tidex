import SwiftUI

/// The break, tax and payday settings a job's pay uses, in words. Setup no longer asks about
/// them, so Home shows this once after the first shift.
internal struct PayAssumptions: Equatable {
  private static let lastPayrollDay = 31

  internal let jobId: String
  internal let summary: String
  /// An hourly wage with no supplement rules, where evening or weekend pay is likely missing.
  internal let suggestsSupplements: Bool

  internal init(job: Job, snapshot: WageSnapshot) {
    var clauses: [String] = []

    if snapshot.effectiveBreakEnabled {
      let threshold = snapshot.effectiveBreakThresholdHours.formatted(
        .number.precision(.fractionLength(0...1)).locale(.appLocale))
      clauses.append(
        String(
          localized: .dashboardPayAssumptionsBreak(
            snapshot.effectiveBreakDeductionMinutes, threshold)))
    } else {
      clauses.append(String(localized: .dashboardPayAssumptionsNoBreak))
    }

    if snapshot.effectiveTaxEnabled {
      let percent = (snapshot.effectiveTaxPercentage / 100).formatted(
        .percent.precision(.fractionLength(0...1)).locale(.appLocale))
      clauses.append(String(localized: .dashboardPayAssumptionsTax(percent)))
    } else {
      clauses.append(String(localized: .dashboardPayAssumptionsNoTax))
    }

    if let payday = Self.paydayClause(for: job) {
      clauses.append(payday)
    }

    jobId = job.id
    summary = String(
      localized: .dashboardPayAssumptionsSummary(
        clauses.formatted(.list(type: .and).locale(.appLocale))))
    suggestsSupplements = snapshot.tariff_type_id == nil && snapshot.supplements.rules.isEmpty
  }

  /// Biweekly pay has no fixed day of the month, so it gets no payday clause.
  private static func paydayClause(for job: Job) -> String? {
    if case .biweekly = job.pay_period {
      return nil
    }
    guard let day = job.payroll_day else {
      return nil
    }
    if day >= lastPayrollDay {
      return String(localized: .dashboardPayAssumptionsPaydayLast)
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    formatter.locale = .appLocale
    let ordinal = formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    return String(localized: .dashboardPayAssumptionsPayday(ordinal))
  }
}

/// Dismissible card that states the pay assumptions and opens the job's pay settings.
internal struct PayAssumptionsCard: View {
  internal let assumptions: PayAssumptions
  internal let onReview: () -> Void
  internal let onDismiss: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  internal var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      message
      buttons
    }
    .padding(Spacing.md)
    .background(
      Color.tidexSurfacePrimary,
      in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
  }

  private var message: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(.dashboardPayAssumptionsTitle)
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextPrimary)
        .accessibilityAddTraits(.isHeader)

      Text(assumptions.summary)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      if assumptions.suggestsSupplements {
        Text(.dashboardPayAssumptionsSupplements)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var buttons: some View {
    buttonLayout {
      Button {
        Haptics.play(.light)
        onReview()
      } label: {
        Text(.dashboardPayAssumptionsReview)
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexTextOnBrand)
          .padding(.horizontal, Spacing.md)
          .frame(minHeight: 44)
          .background(Color.tidexBrandPrimary, in: Capsule())
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("pay-assumptions.review")

      Button {
        Haptics.play(.light)
        onDismiss()
      } label: {
        Text(.commonOk)
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexBlueText)
          .padding(.horizontal, Spacing.md)
          .frame(minHeight: 44)
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("pay-assumptions.dismiss")
    }
  }

  private var buttonLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.xs))
  }
}
