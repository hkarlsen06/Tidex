import SwiftUI

/// The month's pay: caption, amount, what the amount means, and the change from the previous
/// month, followed by the hours, shifts and pay per hour.
struct StatsHero: View {
  let hero: StatsLattice.Hero
  let metrics: StatsLattice.Metrics

  @Environment(\.userCurrency) private var currency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isBreakdownShown: Bool = false

  private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: 0) {
        summary
        changeRow
      }
      StatsMetricStrip(metrics: metrics)
    }
    .onChange(of: hero.month) {
      isBreakdownShown = false
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(caption)
        .statsSlot()
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextSecondary)
        .padding(.bottom, Spacing.xxxs)
      Text(amount)
        .contentTransition(reduceMotion ? .identity : .numericText(value: hero.amount))
        .monospacedDigit()
        .statsSlot(lines: isAccessibilitySize ? 2 : 1)
        .font(isAccessibilitySize ? .tidexAmountLarge : .tidexHeroAmount)
        .foregroundStyle(Color.tidexTextPrimary)
      HStack(spacing: Spacing.xs) {
        Text(qualifier)
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .leading)
        currencyChip
      }
      .statsSlot(lines: isAccessibilitySize ? 2 : 1)
      .font(.tidexSubheadline)
      .foregroundStyle(Color.tidexTextSecondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityText))
    .accessibilityAddTraits([.isHeader, .isStaticText])
    .accessibilityActions {
      if hasOtherCurrencies {
        Button(String(localized: .statsCurrencyBreakdownShow)) {
          isBreakdownShown = true
        }
      }
    }
    .accessibilityIdentifier("stats.hero.amount")
  }

  private var changeRow: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: changeSymbol)
        .font(.tidexCaptionStrong)
        .foregroundStyle(changeColor)
        .accessibilityHidden(true)
      Text(changeText)
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .statsSlot(lines: isAccessibilitySize ? 2 : 1)
    .font(.tidexSubheadline)
    .foregroundStyle(Color.tidexTextSecondary)
    .padding(.top, Spacing.xxs)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityIdentifier("stats.hero.change")
  }

  /// Kept in place with no width when the month has one currency, so the qualifier line
  /// never depends on whether the chip is there.
  private var currencyChip: some View {
    Button {
      Haptics.play(.selection)
      isBreakdownShown.toggle()
    } label: {
      HStack(spacing: Spacing.xxs) {
        Text(chipText)
          .monospacedDigit()
        Image(systemName: "info.circle")
          .accessibilityHidden(true)
      }
      .font(.tidexLabel)
      .foregroundStyle(Color.tidexBlueText)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .fixedSize()
    .frame(maxWidth: hasOtherCurrencies ? nil : 0, alignment: .trailing)
    .opacity(hasOtherCurrencies ? 1 : 0)
    .disabled(!hasOtherCurrencies)
    .accessibilityHidden(true)
    .popover(isPresented: $isBreakdownShown) {
      // The slot's one-line limit would otherwise reach the popover's text.
      MixedCurrencyBreakdownPopover(entries: hero.breakdown)
        .lineLimit(nil)
        .minimumScaleFactor(1)
        .presentationCompactAdaptation(.popover)
    }
  }

  // MARK: Copy

  private var monthName: String {
    StatsFormat.monthName(hero.month, withYear: hero.showsYear)
  }

  private var caption: String {
    let resource: LocalizedStringResource =
      hero.isAfterTax
      ? .statsHeroCaptionAfterTax(monthName) : .statsHeroCaptionBeforeTax(monthName)
    return String(localized: resource).sentenceCased()
  }

  private var amount: AttributedString {
    let option = CurrencyConfig.get(currency)
    let number = AttributedString(CurrencyConfig.formatPlain(hero.amount))
    let unit = StatsFormat.styled(
      option.value,
      font: isAccessibilitySize ? .tidexTitle : .tidexAmountMedium,
      color: .tidexTextMuted
    )
    return option.display == .prefix ? unit + number : number + AttributedString(" ") + unit
  }

  private var qualifier: AttributedString {
    switch hero.qualifier {
    case .noShifts:
      return StatsFormat.plain(String(localized: .statsHeroNoShifts), color: .tidexTextMuted)
    case .untaxed:
      return StatsFormat.plain(String(localized: .statsHeroUntaxed))
    case .taxed(let gross, let taxPercent):
      return StatsFormat.emphasized(
        .statsHeroTaxed(
          StatsFormat.money(gross, currency: currency), StatsFormat.percent(taxPercent)),
        color: .tidexTextPrimary
      )
    }
  }

  private var hasOtherCurrencies: Bool {
    hero.otherCurrencies != .absent
  }

  private var chipText: String {
    switch hero.otherCurrencies {
    case .absent: ""
    case .one(let amount, let otherCurrency):
      String(localized: .statsHeroOtherCurrency(StatsFormat.money(amount, currency: otherCurrency)))
    case .several(let count): String(localized: .statsHeroOtherCurrencies(count))
    }
  }

  private var wholeChange: Double? {
    if case .percent(let change) = hero.change { change.rounded() } else { nil }
  }

  private var changeColor: Color {
    guard let wholeChange else { return .tidexTextMuted }
    if wholeChange > 0 { return .tidexSuccess }
    if wholeChange < 0 { return .tidexError }
    return .tidexTextSecondary
  }

  private var changeSymbol: String {
    guard let wholeChange else { return "minus" }
    if wholeChange > 0 { return "arrow.up.right" }
    if wholeChange < 0 { return "arrow.down.right" }
    return "minus"
  }

  private var changeText: AttributedString {
    let previous = StatsFormat.monthName(hero.previousMonth)
    switch hero.change {
    case .noPreviousPay:
      return StatsFormat.plain(
        String(localized: .statsHeroNoPreviousPay(previous)), color: .tidexTextMuted)
    case .percent(let change):
      return StatsFormat.emphasized(
        .statsHeroChange(MonthlyEarningsChange.percentText(change), previous), color: changeColor)
    }
  }

  private var accessibilityText: String {
    [caption, StatsFormat.money(hero.amount, currency: currency), String(qualifier.characters)]
      .joined(separator: ", ") + (hasOtherCurrencies ? ", \(chipText)" : "")
  }
}

/// Hours, shifts and pay per hour between two hairlines.
private struct StatsMetricStrip: View {
  let metrics: StatsLattice.Metrics

  @Environment(\.userCurrency) private var currency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct Item: Identifiable {
    let id: Int
    let label: String
    let value: String
    let number: Double
  }

  private var items: [Item] {
    [
      Item(
        id: 0, label: String(localized: .statsHours), value: StatsFormat.hours(metrics.hours),
        number: metrics.hours),
      Item(
        id: 1, label: String(localized: .statsShifts), value: StatsFormat.count(metrics.shifts),
        number: Double(metrics.shifts)),
      Item(
        id: 2, label: String(localized: .commonPerHour).sentenceCased(),
        value: metrics.perHour.map { StatsFormat.money($0, currency: currency) } ?? "–",
        number: metrics.perHour ?? 0),
    ]
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          ForEach(items) { item in
            HStack(alignment: .firstTextBaseline) {
              label(item)
              value(item, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
          }
        }
      } else {
        HStack(spacing: 0) {
          ForEach(items) { item in
            column(item)
          }
        }
      }
    }
    .padding(.vertical, Spacing.xs)
    .overlay(alignment: .top) { StatsHairline() }
    .overlay(alignment: .bottom) { StatsHairline() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("stats.metrics")
  }

  private func column(_ item: Item) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      label(item)
      value(item)
    }
    .padding(.leading, item.id == 0 ? 0 : Spacing.msm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Color.tidexSeparator)
        .frame(width: 1)
        .opacity(item.id == 0 ? 0 : 1)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }

  private func label(_ item: Item) -> some View {
    Text(item.label)
      .statsSlot()
      .font(.tidexCaption)
      .foregroundStyle(Color.tidexTextMuted)
  }

  private func value(_ item: Item, alignment: Alignment = .leading) -> some View {
    Text(item.value)
      .contentTransition(reduceMotion ? .identity : .numericText(value: item.number))
      .monospacedDigit()
      .statsSlot(alignment: alignment)
      .font(.tidexTitle)
      .foregroundStyle(Color.tidexTextPrimary)
  }
}
