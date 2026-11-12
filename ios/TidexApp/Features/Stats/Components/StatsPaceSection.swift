import SwiftUI

struct StatsPaceSection: View {
  let pace: StatsLattice.Pace
  var onScrubbingChange: (Bool) -> Void = { _ in }

  @Environment(\.userCurrency) private var currency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var scrub: Scrub = .idle
  @State private var voiceOverDay: Int?

  private enum Scrub: Equatable {
    case idle
    case day(Int)
  }

  private static let plotHeight: CGFloat = 160
  private static let tickDays: [Int] = [1, 7, 14, 21, 28]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsSectionHeader(title: .statsPaceTitle, sentence: headline)
      readout
        .padding(.top, Spacing.xsm)
        .padding(.bottom, Spacing.xs)
      GeometryReader { proxy in
        plot(StatsPaceGeometry(width: proxy.size.width, height: Self.plotHeight, yMax: pace.yMax))
      }
      .frame(height: Self.plotHeight)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(.statsPaceTitle))
      .accessibilityValue(Text(readoutAccessibilityText))
      .accessibilityAdjustableAction(adjustVoiceOverDay)
      .accessibilityChartDescriptor(chartDescriptor)
      .accessibilityIdentifier("stats.pace.plot")
      ticks
        .padding(.top, Spacing.xxs)
    }
    .onChange(of: pace.month) {
      voiceOverDay = nil
    }
    .onChange(of: scrub) { _, newValue in
      onScrubbingChange(newValue != .idle)
      if case .day = newValue {
        Haptics.play(.selection)
      }
    }
  }

  // MARK: Plot

  private func plot(_ geometry: StatsPaceGeometry) -> some View {
    ZStack(alignment: .topLeading) {
      StatsPaceGrid(geometry: geometry)
      StatsPaceHatchShape(startSlot: Double(pace.dayCount))
        .stroke(Color.tidexTextMuted.opacity(0.45), lineWidth: 1)
        .accessibilityHidden(true)
      scaleLabels(geometry)
      ForEach([pace.previous, pace.focus]) { series in
        StatsPaceLine(series: series, yMax: pace.yMax)
          .transition(
            .asymmetric(
              insertion: .modifier(
                active: StatsPaceReveal(progress: 0.001), identity: StatsPaceReveal(progress: 1)),
              removal: .opacity
            ))
      }
      todayMarker(geometry)
      scrubLine(geometry)
    }
    .contentShape(Rectangle())
    .gesture(
      StatsPaceScrubGesture { locationX in
        scrub = locationX.map { .day(geometry.day(at: $0, dayCount: pace.dayCount)) } ?? .idle
      })
  }

  private func scaleLabels(_ geometry: StatsPaceGeometry) -> some View {
    ZStack(alignment: .topLeading) {
      Text(StatsFormat.compact(pace.yMax))
        .offset(y: StatsPaceGeometry.top - 15)
      Text(StatsFormat.compact(pace.yMax / 2))
        .offset(y: geometry.y(pace.yMax / 2) - 15)
    }
    .font(.tidexMicro)
    .monospacedDigit()
    .foregroundStyle(Color.tidexTextMuted)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityHidden(true)
  }

  private func todayMarker(_ geometry: StatsPaceGeometry) -> some View {
    let day = pace.reference.day
    let markerX = geometry.x(day)
    let markerY = geometry.y(pace.focus.values[day - 1])
    return ZStack(alignment: .topLeading) {
      Rectangle()
        .fill(Color.tidexTextPrimary.opacity(0.45))
        .frame(width: 1, height: geometry.height - StatsPaceGeometry.top)
        .offset(x: markerX - 0.5, y: StatsPaceGeometry.top)
      Circle()
        .fill(Color.tidexBlue)
        .overlay(Circle().stroke(Color.tidexBackground, lineWidth: 2.5))
        .frame(width: 11, height: 11)
        .offset(x: markerX - 5.5, y: markerY - 5.5)
    }
    .opacity(isTodayReference ? 1 : 0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func scrubLine(_ geometry: StatsPaceGeometry) -> some View {
    let day = scrubbedDay ?? 1
    return Rectangle()
      .fill(Color.tidexTextPrimary)
      .frame(width: 1, height: geometry.height - StatsPaceGeometry.top)
      .offset(x: geometry.x(day) - 0.5, y: StatsPaceGeometry.top)
      .opacity(scrubbedDay == nil ? 0 : 1)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private var ticks: some View {
    Text(verbatim: "0")
      .hidden()
      .frame(maxWidth: .infinity)
      .overlay {
        GeometryReader { proxy in
          ForEach(Self.tickDays, id: \.self) { day in
            Text(day, format: .number)
              .position(
                x: (CGFloat(day) - 0.5) * proxy.size.width / CGFloat(StatsLattice.daySlots),
                y: proxy.size.height / 2)
          }
        }
      }
      .font(.tidexMicro)
      .monospacedDigit()
      .foregroundStyle(Color.tidexTextMuted)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .accessibilityHidden(true)
  }

  // MARK: Readout

  private var scrubbedDay: Int? {
    if case .day(let day) = scrub { day } else { nil }
  }

  private var readoutDay: Int {
    scrubbedDay ?? voiceOverDay ?? pace.reference.day
  }

  private var isTodayReference: Bool {
    if case .today = pace.reference { true } else { false }
  }

  private var readoutDate: String {
    let date = StatsFormat.dayAndMonth(pace.month, day: readoutDay)
    guard case .today(let today) = pace.reference, today == readoutDay else { return date }
    return String(localized: .statsPaceToday(date))
  }

  private var readout: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.micro))
      : AnyLayout(HStackLayout(spacing: Spacing.xs))
    return layout {
      Text(readoutDate)
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: Spacing.xs) {
        StatsPaceSwatch(isFocus: true)
        Text(swatchText(pace.month, value: pace.focus.values[readoutDay - 1]))
        StatsPaceSwatch(isFocus: false)
        Text(swatchText(pace.previousMonth, value: pace.previous.values[readoutDay - 1]))
      }
      .monospacedDigit()
    }
    .statsSlot(lines: dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    .font(.tidexFootnote)
    .foregroundStyle(Color.tidexTextSecondary)
    .accessibilityHidden(true)
  }

  private func swatchText(_ month: FocusMonth, value: Double) -> AttributedString {
    StatsFormat.plain(StatsFormat.shortMonthName(month) + " ")
      + StatsFormat.styled(
        StatsFormat.money(value, currency: currency), font: .tidexFootnoteStrong,
        color: .tidexTextPrimary)
  }

  private var readoutAccessibilityText: String {
    [
      readoutDate,
      "\(StatsFormat.monthName(pace.month)) "
        + StatsFormat.money(pace.focus.values[readoutDay - 1], currency: currency),
      "\(StatsFormat.monthName(pace.previousMonth)) "
        + StatsFormat.money(pace.previous.values[readoutDay - 1], currency: currency),
    ].joined(separator: ", ")
  }

  private func adjustVoiceOverDay(_ direction: AccessibilityAdjustmentDirection) {
    let current = voiceOverDay ?? pace.reference.day
    switch direction {
    case .increment: voiceOverDay = min(current + 1, pace.dayCount)
    case .decrement: voiceOverDay = max(current - 1, 1)
    @unknown default: break
    }
  }

  // MARK: Copy

  private var headline: AttributedString {
    let month = StatsFormat.monthName(pace.month, withYear: pace.showsYear)
    switch pace.headline {
    case .nothing:
      return StatsFormat.plain(String(localized: .statsPaceNothing(month)), color: .tidexTextMuted)
    case .scheduled(let amount):
      return StatsFormat.plain(String(localized: .statsPaceScheduled(money(amount))))
    case .noPreviousPay(let previous):
      let text = String(localized: .statsPaceNoPreviousPay(StatsFormat.monthName(previous)))
      return StatsFormat.plain(text.sentenceCased(), color: .tidexTextMuted)
    case .running(let difference, let previous):
      let name = StatsFormat.monthName(previous)
      return difference >= 0
        ? StatsFormat.emphasized(.statsPaceAhead(money(difference), name), color: .tidexSuccess)
        : StatsFormat.emphasized(.statsPaceBehind(money(-difference), name), color: .tidexError)
    case .ended(let difference, let previous):
      let name = StatsFormat.monthName(previous)
      return difference >= 0
        ? StatsFormat.emphasized(
          .statsPaceEndedAbove(money(difference), name), color: .tidexSuccess)
        : StatsFormat.emphasized(.statsPaceEndedBelow(money(-difference), name), color: .tidexError)
    }
  }

  private func money(_ amount: Double) -> String {
    StatsFormat.money(amount, currency: currency)
  }

  private var chartDescriptor: StatsLineChartDescriptor {
    let days = Array(1...pace.dayCount)
    return StatsLineChartDescriptor(
      title: String(localized: .statsPaceTitle),
      summary: String(headline.characters),
      xAxisTitle: String(localized: .statsAccessibilityAxisDay),
      yAxisTitle: String(localized: .shiftsEarningsSection),
      xRange: 1...Double(pace.dayCount),
      series: [
        StatsLineChartDescriptor.Series(
          name: StatsFormat.monthName(pace.month),
          points: days.map { (x: Double($0), y: pace.focus.values[$0 - 1]) }),
        StatsLineChartDescriptor.Series(
          name: StatsFormat.monthName(pace.previousMonth),
          points: days.map { (x: Double($0), y: pace.previous.values[$0 - 1]) }),
      ],
      formatValue: { [currency] in StatsFormat.money($0, currency: currency) }
    )
  }
}

/// Touch and hold, then drag. A UIKit long press leaves a drag that starts on the plot to the
/// scroll view until the hold completes, and takes the touch from it afterwards. SwiftUI's
/// long press followed by a drag kept every touch on the plot away from the scroll view.
private struct StatsPaceScrubGesture: UIGestureRecognizerRepresentable {
  /// The finger's x position in the plot, or nil when the scrub ends.
  let onChange: (CGFloat?) -> Void

  func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
    let recognizer = UILongPressGestureRecognizer()  // swiftlint:disable:this explicit_type_interface
    recognizer.minimumPressDuration = 0.2  // swiftlint:disable:this no_magic_numbers
    return recognizer
  }

  func handleUIGestureRecognizerAction(
    _ recognizer: UILongPressGestureRecognizer, context: Context
  ) {
    switch recognizer.state {
    case .began, .changed: onChange(context.converter.localLocation.x)
    default: onChange(nil)
    }
  }
}
