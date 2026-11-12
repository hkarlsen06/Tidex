import SwiftUI

/// The employment line and a counted dot in small, as the legend for the line over the bars.
struct StatsEmploymentSwatch: View {
  var body: some View {
    ZStack {
      Capsule()
        .fill(Color.tidexEmploymentAccent)
        .frame(width: 14, height: 1.5)
      Circle()
        .fill(Color.tidexEmploymentAccent)
        .frame(width: 6, height: 6)
    }
    .accessibilityHidden(true)
  }
}

extension StatsLattice.EmploymentAverage {
  /// "avg 54,1% jan.–okt.", with the percent in the employment color.
  func text(sentenceCased: Bool = false) -> AttributedString {
    let resource: LocalizedStringResource
    switch self {
    case .noCompletedMonths:
      let text = String(localized: .statsYearNoCompletedMonths)
      return StatsFormat.plain(sentenceCased ? text.sentenceCased() : text)
    case .average(let average, let range?):
      resource = .statsYearAverage(StatsFormat.percent(average), range)
    case .average(let average, nil):
      resource = .statsYearAverageAll(StatsFormat.percent(average))
    }
    let text = String(localized: resource)
    return StatsFormat.emphasized(
      sentenceCased ? text.sentenceCased() : text, color: .tidexEmploymentAccent)
  }
}

/// The employment chart on its own. Its scale label hangs in a gutter to its left, which the
/// section leaves beside the columns.
struct StatsEmploymentRow: View {
  let employment: StatsLattice.EmploymentYear

  private let scale: StatsEmploymentScale = .standalone

  private var averageValue: Double? {
    if case .average(let value, _) = employment.average { value } else { nil }
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      StatsRule(lineY: scale.top)
        .stroke(Color.tidexSeparator, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
      StatsRule(lineY: scale.bottom)
        .stroke(Color.tidexSeparator, lineWidth: 1)
      StatsRule(lineY: scale.y(averageValue ?? 0))
        .stroke(
          Color.tidexEmploymentAccent,
          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4])
        )
        .opacity(averageValue == nil ? 0 : 1)
      StatsEmploymentMarks(employment: employment, scale: scale)
    }
    .frame(height: scale.height)
    .overlay(alignment: .topLeading) {
      StatsScaleLabel(text: StatsFormat.percent(100), lineY: scale.top, alignment: .trailing)
        .offset(x: -StatsScaleLabel.gutter)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.statsChartsEmploymentTitle))
    .accessibilityChartDescriptor(descriptor)
    .accessibilityIdentifier("stats.year.employment")
  }

  private var descriptor: StatsCategoryChartDescriptor {
    StatsCategoryChartDescriptor(
      title: String(localized: .statsChartsEmploymentTitle),
      summary: averageValue.map {
        String(localized: .statsAccessibilityChartTotal(StatsFormat.percent($0)))
      },
      categoryAxisTitle: String(localized: .commonMonth),
      valueAxisTitle: String(localized: .statsChartsEmploymentTitle),
      points: employment.months.indices.map { index in
        let name = StatsFormat.monthName(FocusMonth(year: employment.year, month: index + 1))
        let value = employment.months[index].value
        return StatsCategoryChartDescriptor.Point(
          category: name, value: value, label: "\(name), \(StatsFormat.percent(value))")
      },
      formatValue: { StatsFormat.percent($0) }
    )
  }
}

/// The employment line and its month dots, with no frame of their own, so they can also lie over
/// the pay bars.
struct StatsEmploymentMarks: View {
  let employment: StatsLattice.EmploymentYear
  let scale: StatsEmploymentScale
  var lineColor: Color = Color.tidexTextMuted.opacity(0.8)
  /// The small baseline dot of a month with no shifts. Over the pay bars the month's bar stub
  /// already marks it.
  var marksEmptyMonths: Bool = true

  var body: some View {
    ZStack(alignment: .topLeading) {
      StatsEmploymentLine(
        values: StatsVector(employment.months.map(\.value)),
        present: employment.months.map { $0 != .noShifts },
        scale: scale
      )
      .stroke(lineColor, lineWidth: 1.5)
      HStack(spacing: 0) {
        ForEach(employment.months.indices, id: \.self) { index in
          dot(employment.months[index])
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func dot(_ employment: StatsLattice.Employment) -> some View {
    let isCounted: Bool = if case .counted = employment { true } else { false }
    let hasShifts = employment != .noShifts
    return ZStack(alignment: .top) {
      Circle()
        .fill(Color.tidexTextMuted)
        .frame(width: 3, height: 3)
        .offset(y: scale.y(0) - 1.5)
        .opacity(hasShifts || !marksEmptyMonths ? 0 : 0.5)
      Circle()
        .fill(isCounted ? Color.tidexEmploymentAccent : Color.tidexBackground)
        .overlay(
          Circle().stroke(
            isCounted ? Color.tidexBackground : Color.tidexEmploymentAccent, lineWidth: 2)
        )
        .frame(width: 8, height: 8)
        .offset(y: scale.y(employment.value) - 4)
        .opacity(hasShifts ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

private struct StatsEmploymentLine: Shape {
  var values: StatsVector
  let present: [Bool]
  let scale: StatsEmploymentScale

  nonisolated var animatableData: StatsVector {
    get { values }
    set { values = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let column = rect.width / CGFloat(StatsLattice.monthSlots)
    var path = Path()
    for index in present.indices.dropLast() where present[index] && present[index + 1] {
      path.move(
        to: CGPoint(x: (CGFloat(index) + 0.5) * column, y: scale.y(values[index])))
      path.addLine(
        to: CGPoint(x: (CGFloat(index) + 1.5) * column, y: scale.y(values[index + 1])))
    }
    return path
  }
}

/// Where 0 and 100 percent sit in a plot of the given height.
struct StatsEmploymentScale {
  let height: CGFloat
  let top: CGFloat
  let bottom: CGFloat

  /// The employment chart on its own. The top leaves room for the "100%" label under the month
  /// letters.
  static let standalone: StatsEmploymentScale = StatsEmploymentScale(
    height: 92, top: 24, bottom: 86)

  func y(_ percent: Double) -> CGFloat {
    bottom - CGFloat(min(max(percent, 0), 100) / 100) * (bottom - top)
  }
}
