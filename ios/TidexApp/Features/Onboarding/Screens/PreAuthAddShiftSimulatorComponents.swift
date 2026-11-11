import SwiftUI

/// What the demo shift pays, large, with the calculation under it. Plain text, no panel.
struct PreAuthDemoPaySummary: View {
  let pay: PreAuthDemoPay
  let hourlyRate: Double
  let currency: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: CurrencyConfig.format(pay.net, currency: currency))
          .font(.tidexAmountLarge)
          .foregroundStyle(Color.tidexTextPrimary)
          .contentTransition(.numericText(value: pay.net))
          .motionAnimation(.feedback, value: pay.net, reduceMotion: reduceMotion)
        Text(.onboardingAddSimulatorAfterTax)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("onboarding.demo.pay")

      VStack(spacing: Spacing.xxxs) {
        ForEach(pay.lines, id: \.self) { line in
          HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(verbatim: label(for: line.kind))
              .foregroundStyle(Color.tidexTextSecondary)
            Spacer(minLength: 0)
            Text(verbatim: amountText(line.amount))
              .monospacedDigit()
              .foregroundStyle(Color.tidexTextPrimary)
          }
          .font(.tidexSubheadline)
          .accessibilityElement(children: .combine)
        }
      }

      Text(.onboardingAddSimulatorExampleRate(CurrencyConfig.format(hourlyRate, currency: currency)))
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, Spacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func label(for kind: PreAuthDemoPay.Kind) -> String {
    switch kind {
    case .hours(let hours, let rate):
      let hoursText = hours.formatted(.number.precision(.fractionLength(0...2)).locale(.appLocale))
      return String(
        localized: .onboardingAddSimulatorLineHours(hoursText, CurrencyConfig.format(rate, currency: currency)))
    case .supplement(let supplement):
      let percent = percentText(supplement.percent)
      switch supplement {
      case .evening: return String(localized: .onboardingAddSimulatorLineEvening(percent))
      case .saturday: return String(localized: .onboardingAddSimulatorLineSaturday(percent))
      case .sunday: return String(localized: .onboardingAddSimulatorLineSunday(percent))
      }
    case .unpaidBreak(let minutes):
      return String(localized: .onboardingAddSimulatorLineUnpaidBreak(minutes))
    case .tax(let percent):
      return String(localized: .onboardingAddSimulatorLineTax(percentText(percent)))
    }
  }

  private func percentText(_ percent: Double) -> String {
    (percent / 100).formatted(.percent.precision(.fractionLength(0)).locale(.appLocale))
  }

  private func amountText(_ amount: Double) -> String {
    let text = CurrencyConfig.format(abs(amount), currency: currency)
    return amount < 0 ? "\u{2212}\(text)" : text
  }
}
