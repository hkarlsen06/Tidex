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

  private static let plotHeight: CGFloat = 220
  private static let tickDays: [Int] = [1, 7, 14, 21, 28]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsSectionHeader(title: .statsPaceTitle, sentence: headline)
      readout
        .padding(.top, StatsRhythm.headerToBody)
        .padding(.bottom, Spacing.md)
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
        .padding(.top, Spacing.sm)
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
      ForEach([pace.previous, pace.focus]) { series in
        StatsPaceLine(series: series, yMax: pace.yMax)
          .opacity(isAlone && series.role == .previous ? 0 : 1)
          .transition(
            .asymmetric(
              insertion: .modifier(
                active: StatsPaceReveal(progress: 0.001), identity: StatsPaceReveal(progress: 1)),
              removal: .opacity
            ))
      }
      todayMarker(geometry)
      scrubLine(geometry)
      // Inside the plot, where nothing but the today marker on the first days comes near it.
      StatsScaleLabel(
        text: StatsFormat.compact(pace.yMax), lineY: StatsPaceGeometry.top, alignment: .leading,
        hasHalo: true)
    }
    .contentShape(Rectangle())
    .gesture(
      StatsPaceScrubGesture { locationX in
        scrub = locationX.map { .day(geometry.day(at: $0, dayCount: pace.dayCount)) } ?? .idle
      })
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

  /// The month before has no pay, so its line and its legend entry are left out.
  private var isAlone: Bool {
    pace.headline == .alone
  }

  private var isTodayReference: Bool {
    if case .today = pace.reference { true } else { false }
  }

  /// At rest in a finished or future month the values are the month's totals, and the last day's
  /// date beside them explains nothing. The date shows for today and for a day being read.
  private var showsReadoutDate: Bool {
    isTodayReference || scrubbedDay != nil || voiceOverDay != nil
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
        .opacity(showsReadoutDate ? 1 : 0)
      HStack(spacing: Spacing.xs) {
        StatsPaceSwatch(isFocus: true)
        Text(swatchText(pace.month, value: pace.focus.values[readoutDay - 1]))
        if !isAlone {
          StatsPaceSwatch(isFocus: false)
          Text(swatchText(pace.previousMonth, value: pace.previous.values[readoutDay - 1]))
        }
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
    ([readoutDate]
      + shownSeries.map { name, values in
        "\(name) " + StatsFormat.money(values[readoutDay - 1], currency: currency)
      }).joined(separator: ", ")
  }

  /// Each drawn line with its month's name.
  private var shownSeries: [(name: String, values: [Double])] {
    let focus = (name: StatsFormat.monthName(pace.month), values: pace.focus.values)
    let previous = (name: StatsFormat.monthName(pace.previousMonth), values: pace.previous.values)
    return isAlone ? [focus] : [focus, previous]
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
    let resource: LocalizedStringResource =
      switch pace.headline {
      case .versus(let previous): .statsPaceVersus(month, StatsFormat.monthName(previous))
      case .alone: .statsPaceAlone(month)
      }
    return StatsFormat.plain(String(localized: resource).sentenceCased())
  }

  private var chartDescriptor: StatsLineChartDescriptor {
    let days = Array(1...pace.dayCount)
    return StatsLineChartDescriptor(
      title: String(localized: .statsPaceTitle),
      summary: String(headline.characters),
      xAxisTitle: String(localized: .statsAccessibilityAxisDay),
      yAxisTitle: String(localized: .shiftsEarningsSection),
      xRange: 1...Double(pace.dayCount),
      series: shownSeries.map { name, values in
        StatsLineChartDescriptor.Series(
          name: name, points: days.map { (x: Double($0), y: values[$0 - 1]) })
      },
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
