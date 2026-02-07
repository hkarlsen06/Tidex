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
  case hours(HoursData, color: Color = .tidexTextPrimary)

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
  let dayInfo: CalendarDayInfo
  let style: CalendarCellStyle
  let content: CalendarCellContent

  /// Shows a small friends icon indicator (e.g., when both user and friend have shifts)
  var showOverlapIndicator: Bool = false

  /// Optional custom content view (used when content == .custom)
  let customContent: (() -> Content)?

  @Environment(\.layoutDirection) private var layoutDirection

  init(
    dayInfo: CalendarDayInfo,
    style: CalendarCellStyle,
    content: CalendarCellContent,
    showOverlapIndicator: Bool = false,
    @ViewBuilder customContent: @escaping () -> Content
  ) {
    self.dayInfo = dayInfo
    self.style = style
    self.content = content
    self.showOverlapIndicator = showOverlapIndicator
    self.customContent = customContent
  }

  var body: some View {
    ZStack {
      // Week number (top-left corner, only on Mondays, hidden when overlap indicator shows)
      if let weekNum = dayInfo.weekNumber, !showOverlapIndicator {
        VStack {
          HStack {
            Text("\(weekNum)")
              .font(.caption2)
              .foregroundColor(.tidexTextMuted)
              .padding(.leading, Spacing.xxs)
              .padding(.top, 3)
            Spacer()
          }
          Spacer()
        }
      }

      // Day number (top-right corner)
      VStack {
        HStack {
          Spacer()
          Text("\(dayInfo.dayNumber)")
            .font(.caption2.weight(.semibold))
            .foregroundColor(style.dayNumberColor)
            .padding(.trailing, Spacing.xxs)
            .padding(.top, 3)
        }
        Spacer()
      }

      // Overlap indicator (top-left, replacing week number position)
      if showOverlapIndicator {
        VStack {
          HStack {
            Image(systemName: "person.2.fill")
              .font(.system(size: 9, weight: .semibold))
              .foregroundColor(.tidexBlue)
              .padding(.leading, Spacing.xxs)
              .padding(.top, 5)
            Spacer()
          }
          Spacer()
        }
      }

      // Content (centered)
      contentView
    }
    .frame(maxWidth: .infinity)
    .aspectRatio(1 / 1.3, contentMode: .fill)
    .clipped()
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(style.backgroundColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(style.borderColor, lineWidth: style.borderWidth)
    )
    .tidexCardShadow(cornerRadius: 8)
    .opacity(dayInfo.isOutsideMonth ? 0.4 : 1.0)
  }

  @ViewBuilder
  private var contentView: some View {
    switch content {
    case .empty:
      EmptyView()

    case .hours(let hoursData, let color):
      let endDisplay = hoursData.end + (hoursData.crossesMidnight ? "*" : "")
      GeometryReader { geo in
        let fontSize = min(geo.size.width * 0.4, geo.size.height * 0.42)
        VStack(spacing: -1) {
          Text(hoursData.start)
            .font(.system(size: fontSize, weight: .bold))
            .environment(\.layoutDirection, .leftToRight)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .center)
          Text(endDisplay)
            .font(.system(size: fontSize, weight: .bold))
            .environment(\.layoutDirection, .leftToRight)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding(.top, 14)
      .padding(.horizontal, Spacing.xxs)

    case .earnings(let amount, let color):
      GeometryReader { geo in
        let fontSize = min(geo.size.width * 0.4, geo.size.height * 0.42)
        Text(CalendarGridHelper.formatCompactCurrency(amount))
          .font(.system(size: fontSize, weight: .bold))
          .foregroundColor(color)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .allowsTightening(true)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding(.top, 14)
      .padding(.horizontal, Spacing.xxs)

    case .earningsBreakdown(let earnings, let color, let beforeTaxColor):
      GeometryReader { geo in
        if earnings.hasTaxEnabled {
          let primarySize = min(geo.size.width * 0.4, geo.size.height * 0.42)
          let secondarySize = primarySize * 0.8
          VStack(spacing: -1) {
            Text(CalendarGridHelper.formatCompactCurrency(earnings.net))
              .font(.system(size: primarySize, weight: .bold))
              .foregroundColor(color)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
              .allowsTightening(true)
              .frame(maxWidth: .infinity, alignment: .center)
            Text(CalendarGridHelper.formatCompactCurrency(earnings.gross))
              .font(.system(size: secondarySize, weight: .bold))
              .foregroundColor(beforeTaxColor)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
              .allowsTightening(true)
              .frame(maxWidth: .infinity, alignment: .center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          let fontSize = min(geo.size.width * 0.4, geo.size.height * 0.42)
          Text(CalendarGridHelper.formatCompactCurrency(earnings.gross))
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .padding(.top, 14)
      .padding(.horizontal, Spacing.xxs)

    case .starIcon(let color):
      VStack {
        Spacer()
        Image(systemName: "star.fill")
          .font(.footnote.weight(.bold))
          .foregroundColor(color)
          .padding(.bottom, Spacing.xs)
      }

    case .dot(let color):
      VStack {
        Spacer()
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
          .padding(.bottom, Spacing.xs)
      }

    case .custom:
      if let customContent = customContent {
        customContent()
      }
    }
  }
}

// MARK: - Convenience Init (No Custom Content)

extension CalendarDayCell where Content == EmptyView {
  init(
    dayInfo: CalendarDayInfo,
    style: CalendarCellStyle,
    content: CalendarCellContent,
    showOverlapIndicator: Bool = false
  ) {
    self.dayInfo = dayInfo
    self.style = style
    self.content = content
    self.showOverlapIndicator = showOverlapIndicator
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
