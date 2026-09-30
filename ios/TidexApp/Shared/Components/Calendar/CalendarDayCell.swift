// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length conditional_returns_on_newline explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface file_length function_parameter_count
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable multiline_arguments_brackets no_magic_numbers number_separator pattern_matching_keywords
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable prefer_self_in_static_references shorthand_optional_binding sorted_enum_cases type_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_contents_order
import SwiftUI

// MARK: - Calendar Cell Style

/// Styling configuration for a calendar day cell
struct CalendarCellStyle {
  let backgroundColor: Color
  let borderColor: Color
  let borderWidth: CGFloat
  let dayNumberColor: Color
  let showsTodayBadge: Bool
  /// Symbol that repeats a highlight state (conflict, new, opened from a widget) that the colors
  /// alone would carry.
  var marker: CalendarCellMarker?

  static let `default` = Self(
    backgroundColor: .tidexSurfacePrimary,
    borderColor: .clear,
    borderWidth: 0,
    dayNumberColor: .tidexTextPrimary,
    showsTodayBadge: false
  )

  static func today() -> Self {
    Self(
      backgroundColor: Color.tidexBlue.opacity(0.2),
      borderColor: .clear,
      borderWidth: 0,
      dayNumberColor: .tidexTextPrimary,
      showsTodayBadge: true
    )
  }

  static func selected() -> Self {
    Self(
      backgroundColor: Color.tidexBlue.opacity(0.10),
      borderColor: .tidexBlue,
      borderWidth: 2,
      dayNumberColor: .tidexTextPrimary,
      showsTodayBadge: false
    )
  }
}

// MARK: - Calendar Cell Marker

/// A small symbol in the corner of a calendar cell, so a highlight is not shown by color alone.
enum CalendarCellMarker: Equatable {
  case conflict
  case newlyAdded
  case deepLink

  /// Conflicts always show their symbol. The brief highlights only show one with
  /// Differentiate Without Color, because the symbol covers part of the shift times.
  func isVisible(differentiateWithoutColor: Bool) -> Bool {
    self == .conflict || differentiateWithoutColor
  }

  var systemImage: String {
    switch self {
    case .conflict:
      return "exclamationmark.triangle.fill"

    case .newlyAdded:
      return "plus.circle.fill"

    case .deepLink:
      return "scope"
    }
  }
}

// MARK: - Calendar Cell Content

/// Content to display in the center of a calendar day cell
enum CalendarCellContent: Equatable {
  /// No content (empty day)
  case empty

  /// Display hours (start and end times)
  case hours(HoursData, color: Color = .tidexTextPrimary, secondaryColor: Color? = nil)

  /// Display earnings amount
  case earnings(Double, color: Color = .tidexTextPrimary)

  /// Display earnings with optional before-tax breakdown
  case earningsBreakdown(
    CalendarEarningsData,
    color: Color = .tidexTextPrimary,
    beforeTaxColor: Color = .tidexTextMuted
  )

  /// Display a star icon (for anchor dates)
  case starIcon(color: Color = .white)

  /// Display a dot indicator (for projected dates)
  case dot(color: Color)

  /// Custom view content (for complex cases)
  case custom
}

// MARK: - Calendar Day Cell

/// Base calendar day cell with consistent layout
/// Handles week number, day number, background, border, and content
struct CalendarDayCell<Content: View>: View {
  @ScaledMetric(relativeTo: .caption) private var metricDynamicTypeScale: CGFloat = 1
  @ScaledMetric(relativeTo: .body) private var defaultTopRowHeight: CGFloat = 17
  @ScaledMetric(relativeTo: .body) private var todayTopRowHeight: CGFloat = 20
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  let dayInfo: CalendarDayInfo
  let style: CalendarCellStyle
  let content: CalendarCellContent
  private let topCornerInset: CGFloat = 1
  private let leadingMarkerLeadingInset: CGFloat = 3
  private let dayNumberTrailingInset: CGFloat = 2
  private let todayBadgeCornerRadius: CGFloat = CornerRadius.sm
  private let todayBadgeLeadingInset: CGFloat = Spacing.xxs + 1
  private let todayBadgeTrailingInset: CGFloat = 3
  private let todayBadgeTopInset: CGFloat = 1
  private let todayBadgeBottomInset: CGFloat = 2
  private let todayBadgeOverlayColor: Color = .tidexBlue.opacity(0.18)
  private let stackedMetricSpacing: CGFloat = -3
  private let eventIndicatorHorizontalInset: CGFloat = Spacing.sm
  private let eventIndicatorBottomInset: CGFloat = 3
  private let eventIndicatorHeight: CGFloat = 2
  private let eventIndicatorSegmentSpacing: CGFloat = 3
  private let beforeTaxFontScale: CGFloat = 0.8

  /// Shows a small friends icon indicator (e.g., when both user and friend have shifts)
  var showOverlapIndicator: Bool = false
  /// Shows a small single-person icon indicator (e.g., when only one user has shifts)
  var showSingleUserIndicator: Bool = false
  /// Tint color for the single-person indicator (a neutral identity color, not a status color)
  var singleUserIndicatorColor: Color = .tidexTextPrimary
  /// SF Symbol for the single-person indicator. When nil, "only you" (the default color) shows
  /// `person.fill` and any other color, "only the friend", shows `person.crop.circle.fill`, so the
  /// two are told apart by shape and not by color alone.
  var singleUserIndicatorSymbol: String?
  /// Shows a small event-presence indicator in the cell.
  var showEventIndicator: Bool = false
  /// Number of events on this day. Controls how many segments the bottom indicator shows.
  var eventIndicatorCount: Int = 0

  /// Optional custom content view (used when content == .custom)
  let customContent: (() -> Content)?

  init(
    dayInfo: CalendarDayInfo,
    style: CalendarCellStyle,
    content: CalendarCellContent,
    showOverlapIndicator: Bool = false,
    showSingleUserIndicator: Bool = false,
    singleUserIndicatorColor: Color = .tidexTextPrimary,
    singleUserIndicatorSymbol: String? = nil,
    showEventIndicator: Bool = false,
    eventIndicatorCount: Int = 0,
    @ViewBuilder customContent: @escaping () -> Content
  ) {
    self.dayInfo = dayInfo
    self.style = style
    self.content = content
    self.showOverlapIndicator = showOverlapIndicator
    self.showSingleUserIndicator = showSingleUserIndicator
    self.singleUserIndicatorColor = singleUserIndicatorColor
    self.singleUserIndicatorSymbol = singleUserIndicatorSymbol
    self.showEventIndicator = showEventIndicator
    self.eventIndicatorCount = eventIndicatorCount
    self.customContent = customContent
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        leadingMarkerSlot
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, leadingMarkerLeadingInset)

        if !style.showsTodayBadge {
          dayNumberView
            .padding(.trailing, dayNumberTrailingInset)
        }
      }
      .frame(
        height: style.showsTodayBadge ? todayTopRowHeight : defaultTopRowHeight, alignment: .top
      )
      .padding(.top, topCornerInset)

      contentView
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(style.backgroundColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .strokeBorder(style.borderColor, lineWidth: style.borderWidth)
    )
    .overlay(alignment: .topTrailing) {
      if style.showsTodayBadge {
        todayBadgeView
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if let marker = style.marker, marker.isVisible(differentiateWithoutColor: differentiateWithoutColor) {
        Image(systemName: marker.systemImage)
          .font(.tidexMicro)
          .imageScale(.small)
          .foregroundColor(.tidexTextPrimary)
          .padding(2)
          .accessibilityHidden(true)
      }
    }
    .overlay(alignment: .bottom) {
      if displayedEventIndicatorSegmentCount > 0 {
        HStack(spacing: eventIndicatorSegmentSpacing) {
          ForEach(0..<displayedEventIndicatorSegmentCount, id: \.self) { _ in
            RoundedRectangle(cornerRadius: eventIndicatorHeight / 2, style: .continuous)
              .fill(Color.tidexBlue)
              .frame(maxWidth: .infinity)
          }
        }
        .frame(height: eventIndicatorHeight)
        .padding(.horizontal, eventIndicatorHorizontalInset)
        .padding(.bottom, eventIndicatorBottomInset)
      }
    }
    .opacity(dayInfo.isOutsideMonth ? 0.4 : 1.0)
  }

  /// Week number and person indicator sit side by side, so the indicator never hides the week.
  private var leadingMarkerContent: some View {
    HStack(spacing: 1) {
      if let weekNum = dayInfo.weekNumber {
        Text("\(weekNum)")
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
      }
      if showOverlapIndicator {
        Image(systemName: "person.2.fill")
          .font(.tidexMicro)
          .imageScale(.small)
          .foregroundColor(.tidexBlueText)
      } else if showSingleUserIndicator {
        Image(systemName: resolvedSingleUserSymbol)
          .font(.tidexMicro)
          .imageScale(.small)
          .foregroundColor(singleUserIndicatorColor)
      }
    }
    .fixedSize()
  }

  private var resolvedSingleUserSymbol: String {
    if let singleUserIndicatorSymbol { return singleUserIndicatorSymbol }
    return singleUserIndicatorColor == .tidexTextPrimary ? "person.fill" : "person.crop.circle.fill"
  }

  private var leadingMarkerSlot: some View {
    Text("88")
      .font(.tidexMicro)
      .fixedSize(horizontal: true, vertical: false)
      .hidden()
      .accessibilityHidden(true)
      .overlay(alignment: .leading) {
        leadingMarkerContent
      }
  }

  @ViewBuilder
  private var dayNumberView: some View {
    Text("\(dayInfo.dayNumber)")
      .font(.tidexBodyMedium)
      .fixedSize(horizontal: true, vertical: false)
      .monospacedDigit()
      .foregroundColor(style.dayNumberColor)
  }

  private var todayBadgeView: some View {
    Text("\(dayInfo.dayNumber)")
      .font(.tidexBodyMedium)
      .fixedSize(horizontal: true, vertical: false)
      .foregroundColor(.tidexTextOnBrand)
      .padding(.leading, todayBadgeLeadingInset)
      .padding(.trailing, todayBadgeTrailingInset)
      .padding(.top, todayBadgeTopInset)
      .padding(.bottom, todayBadgeBottomInset)
      .background {
        todayBadgeShape
          .fill(Color.tidexBrandPrimary)
          .overlay {
            todayBadgeShape
              .fill(todayBadgeOverlayColor)
          }
      }
  }

  private var todayBadgeShape: some InsettableShape {
    UnevenRoundedRectangle(
      cornerRadii: RectangleCornerRadii(
        topLeading: 0,
        bottomLeading: todayBadgeCornerRadius,
        bottomTrailing: 0,
        topTrailing: todayBadgeCornerRadius
      ),
      style: .continuous
    )
  }

  @ViewBuilder
  private var contentView: some View {
    switch content {
    case .empty:
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .hours(let hoursData, let color, let secondaryColor):
      let endDisplay =
        hoursData.end + (hoursData.crossesMidnight ? CalendarGridHelper.nextDayMarker : "")
      let endColor = secondaryColor ?? color
      metricContainer(lineCount: 2) { fontSize in
        calendarStackedMetricText(
          firstValue: hoursData.start,
          firstColor: color,
          secondValue: endDisplay,
          secondColor: endColor,
          fontSize: fontSize,
          fontWeight: .semibold
        )
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        Text(
          verbatim: CalendarGridHelper.timeRangeAccessibilityText(
            start: hoursData.start,
            end: hoursData.end,
            crossesMidnight: hoursData.crossesMidnight
          )))

    case .earnings(let amount, let color):
      let formattedAmount = CalendarGridHelper.formatCompactCurrency(amount)
      metricContainer(lineCount: 1) { fontSize in
        calendarMetricText(
          formattedAmount,
          color: color,
          fontSize: fontSize,
          fontWeight: .semibold
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

    case .earningsBreakdown(let earnings, let color, let beforeTaxColor):
      Group {
        if earnings.hasTaxEnabled {
          let net = CalendarGridHelper.formatCompactCurrency(earnings.net)
          let gross = CalendarGridHelper.formatCompactCurrency(earnings.gross)
          metricContainer(lineCount: 2) { fontSize in
            // Before-tax amount is smaller and lighter, like the header totals.
            calendarStackedMetricText(
              firstValue: net,
              firstColor: color,
              secondValue: gross,
              secondColor: beforeTaxColor,
              fontSize: fontSize,
              fontWeight: .semibold,
              secondFontScale: beforeTaxFontScale,
              secondFontWeight: .regular
            )
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        } else {
          let gross = CalendarGridHelper.formatCompactCurrency(earnings.gross)
          metricContainer(lineCount: 1) { fontSize in
            calendarMetricText(
              gross,
              color: color,
              fontSize: fontSize,
              fontWeight: .semibold
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: CalendarGridHelper.earningsAccessibilityText(earnings)))

    case .starIcon(let color):
      Image(systemName: "star.fill")
        .font(.footnote.weight(.bold))
        .foregroundColor(color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .dot(let color):
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .custom:
      if let customContent {
        customContent()
      }
    }
  }

  private func metricContainer<Inner: View>(
    lineCount: Int,
    horizontalInset: CGFloat = Spacing.xxs,
    @ViewBuilder content: @escaping (_ fontSize: CGFloat) -> Inner
  ) -> some View {
    GeometryReader { geo in
      let fontSize = metricFontSize(
        for: geo.size,
        lineCount: lineCount,
        horizontalInset: horizontalInset
      )

      content(fontSize)
        .padding(.horizontal, horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
  }

  private func metricFontSize(
    for size: CGSize,
    lineCount: Int,
    horizontalInset: CGFloat
  ) -> CGFloat {
    let safeLineCount = max(lineCount, 1)
    let usableWidth = max(size.width - (horizontalInset * 2), 0)
    let widthBound = usableWidth * 0.4
    let interlineSpacing = CGFloat(max(safeLineCount - 1, 0)) * stackedMetricSpacing
    let usableHeight = max(size.height - interlineSpacing, 0)
    let heightPerLine = usableHeight / CGFloat(safeLineCount)
    let heightBound = heightPerLine * 0.9

    let defaultFitSize = min(widthBound, heightBound)

    // Keep the existing fill behavior at default Dynamic Type, but allow some growth
    // for larger accessibility categories when there is still room in the cell.
    let widthCeiling = widthBound
    let heightCeiling = heightPerLine * 0.98
    let fitCeiling = min(widthCeiling, heightCeiling)
    let dynamicTypeAdjusted = defaultFitSize * metricDynamicTypeScale

    return max(9, min(dynamicTypeAdjusted, fitCeiling))
  }

  private func calendarStackedMetricText(
    firstValue: String,
    firstColor: Color,
    secondValue: String,
    secondColor: Color,
    fontSize: CGFloat,
    fontWeight: Font.Weight,
    secondFontScale: CGFloat = 1,
    secondFontWeight: Font.Weight? = nil
  ) -> some View {
    VStack(spacing: stackedMetricSpacing) {
      calendarMetricText(firstValue, color: firstColor, fontSize: fontSize, fontWeight: fontWeight)
      calendarMetricText(
        secondValue, color: secondColor, fontSize: fontSize * secondFontScale,
        fontWeight: secondFontWeight ?? fontWeight)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private func calendarMetricText(
    _ value: String,
    color: Color,
    fontSize: CGFloat,
    fontWeight: Font.Weight
  ) -> some View {
    Text(value)
      .font(.system(size: fontSize, weight: fontWeight))
      .foregroundColor(color)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .allowsTightening(true)
      .monospacedDigit()
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private var displayedEventIndicatorSegmentCount: Int {
    Self.eventIndicatorSegmentCount(for: resolvedEventIndicatorCount)
  }

  private var resolvedEventIndicatorCount: Int {
    if eventIndicatorCount > 0 {
      return eventIndicatorCount
    }
    return showEventIndicator ? 1 : 0
  }

  static func eventIndicatorSegmentCount(for eventCount: Int) -> Int {
    guard eventCount > 0 else { return 0 }
    return min(eventCount, 3)
  }
}

// MARK: - Convenience Init (No Custom Content)

extension CalendarDayCell where Content == EmptyView {
  init(
    dayInfo: CalendarDayInfo,
    style: CalendarCellStyle,
    content: CalendarCellContent,
    showOverlapIndicator: Bool = false,
    showSingleUserIndicator: Bool = false,
    singleUserIndicatorColor: Color = .tidexTextPrimary,
    singleUserIndicatorSymbol: String? = nil,
    showEventIndicator: Bool = false,
    eventIndicatorCount: Int = 0
  ) {
    self.dayInfo = dayInfo
    self.style = style
    self.content = content
    self.showOverlapIndicator = showOverlapIndicator
    self.showSingleUserIndicator = showSingleUserIndicator
    self.singleUserIndicatorColor = singleUserIndicatorColor
    self.singleUserIndicatorSymbol = singleUserIndicatorSymbol
    self.showEventIndicator = showEventIndicator
    self.eventIndicatorCount = eventIndicatorCount
    self.customContent = nil
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.xs) {
    HStack(spacing: Spacing.xxs) {
      CalendarDayCell(
        dayInfo: .inMonth(id: 1, dayNumber: 1, dateISO: "2025-01-01", weekNumber: 1),
        style: .default,
        content: .hours(HoursData(start: "9:00", end: "17:00", crossesMidnight: false))
      )

      CalendarDayCell(
        dayInfo: .inMonth(id: 2, dayNumber: 2, dateISO: "2025-01-02", weekNumber: nil),
        style: .today(),
        content: .earnings(1_500, color: .tidexTextPrimary)
      )

      CalendarDayCell(
        dayInfo: .inMonth(id: 3, dayNumber: 3, dateISO: "2025-01-03", weekNumber: nil),
        style: .selected(),
        content: .empty
      )

      CalendarDayCell(
        dayInfo: .inMonth(id: 4, dayNumber: 4, dateISO: "2025-01-04", weekNumber: nil),
        style: CalendarCellStyle(
          backgroundColor: .tidexBlue,
          borderColor: .tidexBlue,
          borderWidth: 2,
          dayNumberColor: .white,
          showsTodayBadge: false
        ),
        content: .starIcon()
      )
    }
    .frame(height: 70)
  }
  .padding()
  .background(Color.tidexBackground)
}
