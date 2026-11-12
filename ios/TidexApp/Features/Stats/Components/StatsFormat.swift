import SwiftUI

enum StatsFormat {
  private typealias ForegroundColor = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
  private typealias TextFont = AttributeScopes.SwiftUIAttributes.FontAttribute

  static func money(_ amount: Double, currency: String) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  static func hours(_ hours: Double) -> String {
    hours.formatted(.number.precision(.fractionLength(0...1)).locale(Locale.appLocale))
  }

  static func count(_ count: Int) -> String {
    count.formatted(.number.locale(Locale.appLocale))
  }

  /// "54,1%", written the way the employment chart has always shown it.
  static func percent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale.appLocale)) + "%"
  }

  static func compact(_ value: Double) -> String {
    value.formatted(
      .number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale.appLocale))
  }

  static func date(_ month: FocusMonth, day: Int) -> Date {
    Calendar.gregorianCurrent.date(
      from: DateComponents(year: month.year, month: month.month, day: day)) ?? .now
  }

  static func monthName(_ month: FocusMonth, withYear: Bool = false) -> String {
    let style: Date.FormatStyle = withYear ? .dateTime.month(.wide).year() : .dateTime.month(.wide)
    return date(month, day: 1).formatted(style.locale(Locale.appLocale).calendar(.gregorian))
  }

  static func shortMonthName(_ month: FocusMonth) -> String {
    date(month, day: 1).formatted(
      .dateTime.month(.abbreviated).locale(Locale.appLocale).calendar(.gregorian))
  }

  static func dayAndMonth(_ month: FocusMonth, day: Int) -> String {
    date(month, day: day).formatted(
      .dateTime.day().month(.abbreviated).locale(Locale.appLocale).calendar(.gregorian))
  }

  static func weekdayAndDate(_ month: FocusMonth, day: Int) -> String {
    date(month, day: day).formatted(
      .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale.appLocale)
        .calendar(.gregorian))
  }

  static var monthLetters: [String] {
    localeCalendar.veryShortStandaloneMonthSymbols
  }

  /// One letter per weekday, Monday first.
  static var weekdayLetters: [String] {
    let symbols = localeCalendar.veryShortStandaloneWeekdaySymbols
    return Array(symbols.dropFirst()) + symbols.prefix(1)
  }

  private static var localeCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale.appLocale
    return calendar
  }

  /// Catalog copy whose `**marked**` part carries the number. The marked part turns bold and
  /// takes `color`, so the number stands out without a second string that breaks word order.
  static func emphasized(_ resource: LocalizedStringResource, color: Color) -> AttributedString {
    emphasized(String(localized: resource), color: color)
  }

  static func emphasized(_ localized: String, color: Color) -> AttributedString {
    guard
      var text = try? AttributedString(
        markdown: localized,
        options: AttributedString.MarkdownParsingOptions(
          interpretedSyntax: .inlineOnlyPreservingWhitespace))
    else { return AttributedString(localized) }
    let ranges = text.runs
      .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
      .map(\.range)
    for range in ranges {
      text[range][ForegroundColor.self] = color
    }
    return text
  }

  static func plain(_ string: String, color: Color? = nil) -> AttributedString {
    var text = AttributedString(string)
    if let color {
      text[ForegroundColor.self] = color
    }
    return text
  }

  static func styled(_ string: String, font: Font, color: Color) -> AttributedString {
    var text = AttributedString(string)
    text[TextFont.self] = font
    text[ForegroundColor.self] = color
    return text
  }
}

extension View {
  /// Gives text a fixed number of lines of its font, so new copy after a month change cannot
  /// move anything around it. Set the font after this modifier so it sizes the slot too.
  /// A slot of several lines pins its text to the top, so a short string stays where a long
  /// one starts.
  func statsSlot(lines: Int = 1, alignment: HorizontalAlignment = .leading) -> some View {
    StatsSlot(
      lines: lines,
      alignment: Alignment(horizontal: alignment, vertical: lines > 1 ? .top : .center),
      content: self
    )
  }
}

/// The slot's height comes from a hidden line of text in the same font. The visible content
/// sits in an overlay and shrinks to fit, so its string never reaches the layout.
private struct StatsSlot<Content: View>: View {
  let lines: Int
  let alignment: Alignment
  let content: Content

  var body: some View {
    Text(verbatim: "0")
      .lineLimit(lines, reservesSpace: true)
      .hidden()
      .accessibilityHidden(true)
      .frame(maxWidth: .infinity)
      .overlay(alignment: alignment) {
        content
          .lineLimit(lines)
          .minimumScaleFactor(0.5)
          .multilineTextAlignment(textAlignment)
      }
  }

  private var textAlignment: TextAlignment {
    switch alignment.horizontal {
    case .trailing: .trailing
    case .center: .center
    default: .leading
    }
  }
}

/// The vertical rhythm of the Stats page. Whitespace separates the sections, so the gap
/// between two sections is several times the gaps inside one.
enum StatsRhythm {
  static let section: CGFloat = 72
  /// From a section's sentence to the drawing it describes.
  static let headerToBody: CGFloat = 28
  /// A row of the weeks grid or the months ledger.
  static let row: CGFloat = 48
}

struct StatsSectionHeader<Trailing: View>: View {
  let title: LocalizedStringResource
  let sentence: AttributedString
  let trailing: Trailing

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    title: LocalizedStringResource,
    sentence: AttributedString,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.sentence = sentence
    self.trailing = trailing()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        Text(title)
          .tracking(1.4)
          .textCase(.uppercase)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityAddTraits(.isHeader)
        trailing
      }
      .statsSlot()
      .font(.tidexCaption)
      .foregroundStyle(Color.tidexTextMuted)

      Text(sentence)
        .statsSlot(lines: dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .font(.tidexTitle)
        .foregroundStyle(Color.tidexTextPrimary)
    }
  }
}

extension StatsSectionHeader where Trailing == EmptyView {
  init(title: LocalizedStringResource, sentence: AttributedString) {
    self.init(title: title, sentence: sentence) { EmptyView() }
  }
}

struct StatsHairline: View {
  var body: some View {
    Rectangle()
      .fill(Color.tidexSeparator)
      .frame(height: 1)
      .accessibilityHidden(true)
  }
}
