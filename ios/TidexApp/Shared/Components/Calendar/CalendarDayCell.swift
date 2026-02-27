import SwiftUI

// MARK: - Calendar Cell Style

/// Styling configuration for a calendar day cell
struct CalendarCellStyle {
  let backgroundColor: Color
  let borderColor: Color
  let borderWidth: CGFloat
  let dayNumberColor: Color

  static let `default` = CalendarCellStyle(
    backgroundColor: .tidexSurfacePrimary,
    borderColor: .clear,
    borderWidth: 0,
    dayNumberColor: .tidexTextPrimary
  )

  static func today() -> CalendarCellStyle {
    CalendarCellStyle(
      backgroundColor: Color.tidexBlue.opacity(0.2),
      borderColor: .clear,
      borderWidth: 0,
      dayNumberColor: .tidexBlue
    )
  }

  static func selected() -> CalendarCellStyle {
    CalendarCellStyle(
      backgroundColor: Color.tidexBlue.opacity(0.15),
      borderColor: .tidexBlue,
      borderWidth: 2,
      dayNumberColor: .tidexTextPrimary
    )
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

  let dayInfo: CalendarDayInfo
  let style: CalendarCellStyle
  let content: CalendarCellContent
  private let horizontalCornerInset: CGFloat = Spacing.xxxs
  private let topCornerInset: CGFloat = 1
  private let topRowHeight: CGFloat = 17
  private let stackedMetricSpacing: CGFloat = -3

  /// Shows a small friends icon indicator (e.g., when both user and friend have shifts)
  var showOverlapIndicator: Bool = false
  /// Shows a small single-person icon indicator (e.g., when only one user has shifts)
  var showSingleUserIndicator: Bool = false
  /// Tint color for the single-person indicator (e.g., green for you, red for friend)
  var singleUserIndicatorColor: Color = .tidexSuccess

  /// Optional custom content view (used when content == .custom)
  let customContent: (() -> Content)?

  init(
    dayInfo: CalendarDayInfo,
    style: CalendarCellStyle,
    content: CalendarCellContent,
    showOverlapIndicator: Bool = false,
    showSingleUserIndicator: Bool = false,
    singleUserIndicatorColor: Color = .tidexSuccess,
    @ViewBuilder customContent: @escaping () -> Content
  ) {
    self.dayInfo = dayInfo
    self.style = style
    self.content = content
    self.showOverlapIndicator = showOverlapIndicator
    self.showSingleUserIndicator = showSingleUserIndicator
    self.singleUserIndicatorColor = singleUserIndicatorColor
    self.customContent = customContent
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center) {
        leadingMarkerSlot

        Spacer(minLength: 0)

        Text("\(dayInfo.dayNumber)")
          .font(.tidexBodyMedium)
          .fixedSize(horizontal: true, vertical: false)
          .foregroundColor(style.dayNumberColor)
      }
      .frame(height: topRowHeight, alignment: .top)
      .padding(.horizontal, horizontalCornerInset)
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
    .tidexCardShadow(cornerRadius: CornerRadius.sm)
    .opacity(dayInfo.isOutsideMonth ? 0.4 : 1.0)
  }

  @ViewBuilder
  private var leadingMarkerContent: some View {
    if showOverlapIndicator {
      Image(systemName: "person.2.fill")
        .font(.tidexMicro)
        .imageScale(.small)
        .foregroundColor(.tidexBlue)
    } else if showSingleUserIndicator {
      Image(systemName: "person.fill")
        .font(.tidexMicro)
        .imageScale(.small)
        .foregroundColor(singleUserIndicatorColor)
    } else if let weekNum = dayInfo.weekNumber {
      Text("\(weekNum)")
        .font(.tidexMicro)
        .foregroundColor(.tidexTextMuted)
    }
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
  private var contentView: some View {
    switch content {
    case .empty:
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .hours(let hoursData, let color, let secondaryColor):
      let endDisplay = hoursData.end + (hoursData.crossesMidnight ? "*" : "")
      let endColor = secondaryColor ?? color
      metricContainer(lineCount: 2) { fontSize in
        calendarStackedMetricText(
          firstValue: hoursData.start,
          firstColor: color,
          secondValue: endDisplay,
          secondColor: endColor,
          fontSize: fontSize,
          fontWeight: .bold
        )
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

    case .earnings(let amount, let color):
      let formattedAmount = CalendarGridHelper.formatCompactCurrency(amount)
      metricContainer(lineCount: 1) { fontSize in
        calendarMetricText(
          formattedAmount,
          color: color,
          fontSize: fontSize,
          fontWeight: .bold
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

    case .earningsBreakdown(let earnings, let color, let beforeTaxColor):
      Group {
        if earnings.hasTaxEnabled {
          let net = CalendarGridHelper.formatCompactCurrency(earnings.net)
          let gross = CalendarGridHelper.formatCompactCurrency(earnings.gross)
          metricContainer(lineCount: 2) { fontSize in
            calendarStackedMetricText(
              firstValue: net,
              firstColor: color,
              secondValue: gross,
              secondColor: beforeTaxColor,
              fontSize: fontSize,
              fontWeight: .bold
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
              fontWeight: .bold
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }

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
      if let customContent = customContent {
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
    fontWeight: Font.Weight
  ) -> some View {
    VStack(spacing: stackedMetricSpacing) {
      calendarMetricText(firstValue, color: firstColor, fontSize: fontSize, fontWeight: fontWeight)
      calendarMetricText(
        secondValue, color: secondColor, fontSize: fontSize, fontWeight: fontWeight)
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
}

// MARK: - Convenience Init (No Custom Content)

extension CalendarDayCell where Content == EmptyView {
  init(
    dayInfo: CalendarDayInfo,
    style: CalendarCellStyle,
    content: CalendarCellContent,
    showOverlapIndicator: Bool = false,
    showSingleUserIndicator: Bool = false,
    singleUserIndicatorColor: Color = .tidexSuccess
  ) {
    self.dayInfo = dayInfo
    self.style = style
    self.content = content
    self.showOverlapIndicator = showOverlapIndicator
    self.showSingleUserIndicator = showSingleUserIndicator
    self.singleUserIndicatorColor = singleUserIndicatorColor
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
        content: .earnings(1500, color: .tidexTextPrimary)
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
          dayNumberColor: .white
        ),
        content: .starIcon()
      )
    }
    .frame(height: 70)
  }
  .padding()
  .background(Color.tidexBackground)
}
