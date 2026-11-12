import SwiftUI

struct StatsPaceGeometry {
  /// Room above the scale's top line for its label.
  static let top: CGFloat = 14

  let width: CGFloat
  let height: CGFloat
  let yMax: Double

  private var slot: CGFloat { width / CGFloat(StatsLattice.daySlots) }

  func x(_ day: Int) -> CGFloat {
    (CGFloat(day) - 0.5) * slot
  }

  func y(_ value: Double) -> CGFloat {
    let share = yMax > 0 ? min(max(value / yMax, 0), 1) : 0
    return Self.top + (1 - CGFloat(share)) * (height - Self.top - 1)
  }

  func day(at xPosition: CGFloat, dayCount: Int) -> Int {
    guard slot > 0, xPosition.isFinite else { return 1 }
    return min(max(Int((xPosition / slot).rounded(.down)) + 1, 1), dayCount)
  }
}

/// One month's line. A role change crossfades the solid and dotted blue layers with the dashed
/// grey one, because SwiftUI cannot interpolate between dash patterns.
struct StatsPaceLine: View {
  let series: StatsLattice.PaceSeries
  let yMax: Double

  private var isFocus: Bool { series.role == .focus }
  private var values: StatsVector { StatsVector(series.values) }

  var body: some View {
    ZStack {
      StatsPaceLineShape(
        values: values, yMax: yMax, days: 0...series.solidThrough, closesArea: true
      )
      .fill(
        LinearGradient(
          colors: [Color.tidexBlue.opacity(0.34), Color.tidexBlue.opacity(0)],
          startPoint: .top, endPoint: .bottom)
      )
      .opacity(isFocus ? 1 : 0)
      StatsPaceLineShape(values: values, yMax: yMax, days: 0...series.solidThrough)
        .stroke(
          Color.tidexBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
        .opacity(isFocus ? 1 : 0)
      StatsPaceLineShape(values: values, yMax: yMax, days: series.solidThrough...series.dayCount)
        .stroke(
          Color.tidexBlue,
          style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [0.5, 7])
        )
        .opacity(isFocus ? 1 : 0)
      StatsPaceLineShape(values: values, yMax: yMax, days: 0...series.dayCount)
        .stroke(Color.tidexTextMuted, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        .opacity(isFocus ? 0 : 1)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct StatsPaceReveal: ViewModifier {
  let progress: CGFloat

  func body(content: Content) -> some View {
    content.mask(alignment: .leading) {
      Rectangle().scaleEffect(x: progress, y: 1, anchor: .leading)
    }
  }
}

/// Day 0 is the baseline at the plot's leading edge, so every line starts from zero.
struct StatsPaceLineShape: Shape {
  var values: StatsVector
  var yMax: Double
  let days: ClosedRange<Int>
  var closesArea: Bool = false

  nonisolated var animatableData: AnimatablePair<StatsVector, Double> {
    get { AnimatablePair(values, yMax) }
    set {
      values = newValue.first
      yMax = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let geometry = StatsPaceGeometry(width: rect.width, height: rect.height, yMax: yMax)
    var path = Path()
    for day in days {
      let point = CGPoint(
        x: day == 0 ? 0 : geometry.x(day), y: geometry.y(day == 0 ? 0 : values[day - 1]))
      if day == days.lowerBound {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    if closesArea, days.upperBound > 0 {
      path.addLine(to: CGPoint(x: geometry.x(days.upperBound), y: geometry.y(0)))
      path.closeSubpath()
    }
    return path
  }
}

/// Diagonal hatching over the slots after the month's last day, so a short month ends early.
struct StatsPaceHatchShape: Shape {
  var startSlot: Double

  nonisolated var animatableData: Double {
    get { startSlot }
    set { startSlot = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let spacing: CGFloat = 6
    let minX = CGFloat(startSlot) * rect.width / CGFloat(StatsLattice.daySlots)
    let minY = StatsPaceGeometry.top
    var path = Path()
    guard rect.maxX - minX > 0.5 else { return path }
    // Each line is x + y = intercept, so the pattern stays put while the edge moves.
    var intercept = ((minX + minY) / spacing).rounded(.up) * spacing
    while intercept <= rect.maxX + rect.maxY {
      let start = max(minX, intercept - rect.maxY)
      let end = min(rect.maxX, intercept - minY)
      if start < end {
        path.move(to: CGPoint(x: start, y: intercept - start))
        path.addLine(to: CGPoint(x: end, y: intercept - end))
      }
      intercept += spacing
    }
    return path
  }
}

struct StatsPaceGrid: View {
  let geometry: StatsPaceGeometry

  var body: some View {
    ZStack {
      Path { path in
        // The top line starts after its scale label.
        path.move(to: CGPoint(x: StatsScaleLabel.gutter, y: StatsPaceGeometry.top))
        path.addLine(to: CGPoint(x: geometry.width, y: StatsPaceGeometry.top))
        let middle = geometry.y(geometry.yMax / 2)
        path.move(to: CGPoint(x: 0, y: middle))
        path.addLine(to: CGPoint(x: geometry.width, y: middle))
      }
      .stroke(Color.tidexSeparator, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
      Path { path in
        path.move(to: CGPoint(x: 0, y: geometry.height - 0.5))
        path.addLine(to: CGPoint(x: geometry.width, y: geometry.height - 0.5))
      }
      .stroke(Color.tidexSeparator, lineWidth: 1)
    }
    .accessibilityHidden(true)
  }
}

struct StatsPaceSwatch: View {
  let isFocus: Bool

  var body: some View {
    Path { path in
      path.move(to: CGPoint(x: 0, y: 1))
      path.addLine(to: CGPoint(x: 12, y: 1))
    }
    .stroke(
      isFocus ? Color.tidexBlue : Color.tidexTextMuted,
      style: StrokeStyle(lineWidth: 2, dash: isFocus ? [] : [3, 2])
    )
    .frame(width: 12, height: 2)
    .accessibilityHidden(true)
  }
}

/// 31 cumulative values, so a line can animate between months point by point.
struct StatsVector: VectorArithmetic {
  var values: [Double]

  init(_ values: [Double]) {
    self.values = values
  }

  static var zero: StatsVector { StatsVector([]) }

  var magnitudeSquared: Double {
    values.reduce(0) { $0 + $1 * $1 }
  }

  /// Missing entries read as zero, so the empty `zero` vector combines with any other.
  subscript(index: Int) -> Double {
    values.indices.contains(index) ? values[index] : 0
  }

  static func + (lhs: StatsVector, rhs: StatsVector) -> StatsVector {
    combine(lhs, rhs, +)
  }

  static func - (lhs: StatsVector, rhs: StatsVector) -> StatsVector {
    combine(lhs, rhs, -)
  }

  mutating func scale(by rhs: Double) {
    values = values.map { $0 * rhs }
  }

  private static func combine(
    _ lhs: StatsVector, _ rhs: StatsVector, _ operation: (Double, Double) -> Double
  ) -> StatsVector {
    StatsVector(
      (0..<max(lhs.values.count, rhs.values.count)).map { operation(lhs[$0], rhs[$0]) })
  }
}
