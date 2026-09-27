#if DEBUG
  import SwiftUI

  /// Money amounts in the states the fixture account can't reach: payday, mixed currencies,
  /// payroll adjustments and a payout that mixes net and gross jobs.
  /// TIDEX_DESIGN_SCREEN=money shows the Home and header amounts, money-payroll the payout details.
  internal struct DesignReviewMoneyCards: View {
    let screen: String
    @State private var isMarkedReceived: Bool = false

    internal var body: some View {
      if screen == "money-payroll" {
        PayrollDetailsSheet(variant: Self.mixedBasisVariant)
      } else {
        ScrollView {
          VStack(spacing: Spacing.lg) {
            TotalCard(
              gross: 28_000, net: 22_400, completedGross: 28_000, completedNet: 22_400,
              shiftCount: 14, plannedCount: 0, percentageChange: 16.67, taxEnabled: true,
              monthName: "September",
              showsCurrencyBreakdownCue: true,
              isElevated: false
            )
            PayrollCard(
              payrollDate: .now, label: String(localized: .dashboardNextPayout),
              gross: 24_600, net: 19_680, tax: 4_920, taxEnabled: true,
              hasPayrollAdjustments: true, isElevated: false,
              isMarkedReceived: isMarkedReceived,
              onToggleReceived: { isMarkedReceived.toggle() }
            )
            CalendarHeaderRow(
              monthName: "September", year: 2_026, selectionCount: nil, phase: nil,
              totals: CalendarHeaderTotals(primary: 22_400, secondary: 28_000),
              trailingAccessory: nil
            )
            CalendarHeaderRow(
              monthName: "September", year: 2_026, selectionCount: nil, phase: nil,
              totals: CalendarHeaderTotals(
                primary: 24_000, secondary: 1_600,
                primaryIsAfterTax: true
              ),
              trailingAccessory: nil, secondaryStyle: .delta
            )
          }
          .padding(Spacing.xxl)
        }
        .background(Color.tidexBackground)
      }
    }

    private static let payoutDate: Date = Date.fromISODateString("2026-10-15") ?? .now

    private static var mixedBasisVariant: PayrollCardVariant {
      let taxed = PayrollCardJobBreakdown(
        id: "nord", title: "Nord", colorHex: nil, currency: "kr",
        basePay: 20_000, supplementPay: 2_000, supplementBreakdowns: [],
        postDeductions: 450,
        postDeductionParts: [
          BreakDeductionPart(
            id: "break", kind: .base, supplementSegment: nil, hours: 2, rate: 225, amount: 450)
        ],
        payoutDate: payoutDate, gross: 21_050, net: 16_840, tax: 4_210, taxEnabled: true,
        adjustments: [uniformDeduction]
      )
      let untaxed = PayrollCardJobBreakdown(
        id: "harbour", title: "Harbour", colorHex: nil, currency: "kr",
        basePay: 6_000, supplementPay: 0, supplementBreakdowns: [],
        postDeductions: 0, postDeductionParts: [],
        payoutDate: payoutDate, gross: 6_000, net: nil, tax: nil, taxEnabled: false,
        adjustments: []
      )
      return PayrollCardVariant(
        id: "mixed", title: String(localized: .dashboardNextPayout), colorHex: nil, badges: [],
        currency: "kr", payoutDate: payoutDate, gross: 27_050, net: 22_840, tax: 4_210,
        taxEnabled: true, hasPayrollAdjustments: true, jobBreakdowns: [taxed, untaxed]
      )
    }

    private static var uniformDeduction: PayrollAdjustment {
      PayrollAdjustment(
        id: "uniform", user_id: "design-preview", job_id: "nord", amount: -500, currency: "kr",
        category: .correction, tax_treatment: .grossTaxable, description: "Uniform",
        note: nil, curated_note: nil, curated_description: nil, curated_link: nil,
        curated_link_title: nil, earned_from_date: nil, earned_to_date: nil,
        payout_date: "2026-10-15", created_at: nil, updated_at: nil, revision: nil,
        deleted_at: nil
      )
    }
  }
#endif
