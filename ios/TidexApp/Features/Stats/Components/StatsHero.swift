import SwiftUI

struct StatsHero: View {
  let hero: StatsLattice.Hero
  let metrics: StatsLattice.Metrics

  @Environment(\.userCurrency) private var currency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isBreakdownShown: Bool = false

  private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

  var body: some View {
    VStack(spacing: Spacing.xxxl) {
      VStack(spacing: 0) {
        summary
        changeRow
      }
      StatsMetricStrip(metrics: metrics)
    }
    .padding(.top, Spacing.lg)
    .onChange(of: hero.period) {
      isBreakdownShown = false
    }
  }

  private var summary: some View {
    VStack(spacing: 0) {
      Text(caption)
        .statsSlot(alignment: .center)
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextSecondary)
        .padding(.bottom, Spacing.xs)
      Text(amount)
        .contentTransition(reduceMotion ? .identity : .numericText(value: hero.amount))
        .monospacedDigit()
        .statsSlot(lines: isAccessibilitySize ? 2 : 1, alignment: .center)
        .font(isAccessibilitySize ? .tidexAmountLarge : .tidexHeroAmount)
        .foregroundStyle(Color.tidexTextPrimary)
      HStack(spacing: hasOtherCurrencies ? Spacing.xs : 0) {
        Text(qualifier)
          .monospacedDigit()
        currencyChip
      }
      .statsSlot(lines: isAccessibilitySize ? 2 : 1, alignment: .center)
      .font(.tidexSubheadline)
      .foregroundStyle(Color.tidexTextSecondary)
      .padding(.top, Spacing.xs)
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
    }
    .statsSlot(lines: isAccessibilitySize ? 2 : 1, alignment: .center)
    .font(.tidexSubheadline)
    .foregroundStyle(Color.tidexTextSecondary)
    .padding(.top, Spacing.xs)
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

  private var periodName: String {
    switch hero.period {
    case .month(let month, let showsYear): StatsFormat.monthName(month, withYear: showsYear)
    case .year(let year): String(year)
    }
  }

  private var previousPeriodName: String {
    switch hero.period {
    case .month(let month, _): StatsFormat.monthName(month.previous)
    case .year(let year): String(year - 1)
    }
  }

  private var caption: String {
    let resource: LocalizedStringResource =
      hero.isAfterTax
      ? .statsHeroCaptionAfterTax(periodName) : .statsHeroCaptionBeforeTax(periodName)
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
    case .taxed(let gross, let taxPercent?):
      return StatsFormat.emphasized(
        .statsHeroTaxed(
          StatsFormat.money(gross, currency: currency), StatsFormat.percent(taxPercent)),
        color: .tidexTextPrimary
      )
    case .taxed(let gross, nil):
      return StatsFormat.emphasized(
        .statsHeroTaxedYear(StatsFormat.money(gross, currency: currency)),
        color: .tidexTextPrimary)
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
    switch hero.change {
    case .percent(let change), .percentSameTime(let change): change.rounded()
    case .noPreviousPay: nil
    }
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
    let previous = previousPeriodName
    switch hero.change {
    case .noPreviousPay:
      return StatsFormat.plain(
        String(localized: .statsHeroNoPreviousPay(previous)), color: .tidexTextMuted)
    case .percent(let change):
      return StatsFormat.emphasized(
        .statsHeroChange(MonthlyEarningsChange.percentText(change), previous), color: changeColor)
    case .percentSameTime(let change):
      return StatsFormat.emphasized(
        .statsHeroChangeSameTime(MonthlyEarningsChange.percentText(change), previous),
        color: changeColor)
    }
  }

  private var accessibilityText: String {
    [caption, StatsFormat.money(hero.amount, currency: currency), String(qualifier.characters)]
      .joined(separator: ", ") + (hasOtherCurrencies ? ", \(chipText)" : "")
  }
}

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
        VStack(alignment: .leading, spacing: Spacing.md) {
          ForEach(items) { item in
            HStack(alignment: .firstTextBaseline) {
              label(item, alignment: .leading)
              value(item, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
          }
        }
      } else {
        HStack(spacing: Spacing.md) {
          ForEach(items) { item in
            column(item)
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("stats.metrics")
  }

  private func column(_ item: Item) -> some View {
    VStack(spacing: Spacing.xxxs) {
      value(item, alignment: .center)
      label(item, alignment: .center)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private func label(_ item: Item, alignment: HorizontalAlignment) -> some View {
    Text(item.label)
      .statsSlot(alignment: alignment)
      .font(.tidexFootnote)
      .foregroundStyle(Color.tidexTextMuted)
  }

  private func value(_ item: Item, alignment: HorizontalAlignment) -> some View {
    Text(item.value)
      .contentTransition(reduceMotion ? .identity : .numericText(value: item.number))
      .monospacedDigit()
      .statsSlot(alignment: alignment)
      .font(.tidexLargeTitle)
      .foregroundStyle(Color.tidexTextPrimary)
  }
}
