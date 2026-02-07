import SwiftUI

/// A shareable view that renders the calendar for sharing as a PNG
/// Displays the calendar in hours mode (from-to times) with optional earnings display
struct ShareableCalendarView: View {
  let shifts: [ShiftWithComputations]
  let year: Int
  let month: Int
  let currency: String
  let includeEarnings: Bool
  let excludedFromTotalIds: Set<String>

  /// The color scheme to use for rendering
  var colorScheme: ColorScheme = .light

  // MARK: - Computed Properties

  private var monthName: String {
    CalendarGridHelper.monthName(
      year: year,
      month: month,
      locale: Locale.appLocale
    )
  }

  /// Hours by ISO date string (for cell content)
  private var hoursByDate: [String: HoursData] {
    var shiftsByDateDict: [String: [ShiftWithComputations]] = [:]
    for shift in shifts {
      shiftsByDateDict[shift.shiftDate, default: []].append(shift)
    }

    var result: [String: HoursData] = [:]
    for (date, shiftsOnDate) in shiftsByDateDict {
      let sorted = shiftsOnDate.sorted { $0.startTime < $1.startTime }
      let earliestStart = sorted.first?.startTime ?? ""
      let latestEnd = sorted.map(\.endTime).max() ?? ""

      let crossesMidnight = shiftsOnDate.contains { shift in
        let startMinutes = CalendarGridHelper.timeToMinutes(shift.startTime)
        let endMinutes = CalendarGridHelper.timeToMinutes(shift.endTime)
        return endMinutes <= startMinutes
      }

      result[date] = HoursData(
        start: CalendarGridHelper.formatTime(earliestStart),
        end: CalendarGridHelper.formatTime(latestEnd),
        crossesMidnight: crossesMidnight
      )
    }
    return result
  }

  /// Monthly totals (net and gross, excludes conflicting shifts)
  private var monthlyTotals: (net: Double, gross: Double) {
    let calendar = Calendar.current
    let filteredShifts = shifts.filter { shift in
      // Skip shifts excluded from totals
      guard !excludedFromTotalIds.contains(shift.id) else { return false }
      guard let date = Date.fromISODateString(shift.shiftDate) else { return false }
      let components = calendar.dateComponents([.year, .month], from: date)
      return components.year == year && components.month == month
    }

    let gross = filteredShifts.reduce(0) { $0 + $1.grossPay }
    let net = filteredShifts.reduce(0) {
      $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay)
    }
    return (net: net, gross: gross)
  }

  /// Whether tax is enabled for any shift
  private var hasTaxEnabled: Bool {
    shifts.contains { $0.taxEnabled }
  }

  /// Shifts grouped by ISO date string
  private var shiftsByDate: [String: [ShiftWithComputations]] {
    var result: [String: [ShiftWithComputations]] = [:]
    for shift in shifts {
      result[shift.shiftDate, default: []].append(shift)
    }
    return result
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: Spacing.md) {
      // Header with month name and totals
      headerRow

      // Weekday header
      CalendarWeekdayHeader()

      // Calendar grid
      calendarGrid

      // Tidex branding
      HStack(spacing: Spacing.xxs) {
        LogoWatermark(opacity: 1.0)
          .frame(width: 14, height: 14)
        Text("Tidex")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(.top, Spacing.xs)
    }
    .padding(Spacing.mlg)
    .frame(width: 402)  // Match iPhone 16/17 screen width for proper scaling
    .background(Color.tidexBackground)
    .environment(\.colorScheme, colorScheme)
  }

  // MARK: - Header Row

  @ViewBuilder
  private var headerRow: some View {
    HStack {
      // Month name + Year
      HStack(spacing: 6) {
        Text(monthName)
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)

        Text(String(year))
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(.tidexTextMuted)
      }

      Spacer()

      // Monthly total (or skeleton if earnings hidden)
      if includeEarnings {
        earningsDisplay
      } else {
        earningsSkeleton
      }
    }
    .padding(.horizontal, Spacing.xxs)
  }

  /// Earnings display - shows monthly totals
  @ViewBuilder
  private var earningsDisplay: some View {
    let displayAmount = hasTaxEnabled ? monthlyTotals.net : monthlyTotals.gross

    VStack(alignment: .trailing, spacing: 2) {
      if monthlyTotals.gross == 0 {
        Text("—")
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)
      } else {
        Text(CurrencyConfig.format(displayAmount, currency: currency))
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)
      }

      // Gross line (only when tax enabled and has value)
      if hasTaxEnabled && monthlyTotals.gross > 0 {
        Text(CurrencyConfig.format(monthlyTotals.gross, currency: currency))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .frame(minHeight: 36, alignment: .trailing)
  }

  /// Skeleton bars to replace earnings when hidden
  @ViewBuilder
  private var earningsSkeleton: some View {
    VStack(alignment: .trailing, spacing: Spacing.xxs) {
      // Main amount skeleton
      RoundedRectangle(cornerRadius: 4)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 72, height: 17)

      // Secondary amount skeleton (only if tax enabled)
      if hasTaxEnabled {
        RoundedRectangle(cornerRadius: 3)
          .fill(Color.tidexTextMuted.opacity(0.2))
          .frame(width: 56, height: 13)
      }
    }
    .frame(minHeight: 36, alignment: .trailing)
  }

  // MARK: - Calendar Grid

  @ViewBuilder
  private var calendarGrid: some View {
    let days = CalendarGridHelper.daysInMonth(year: year, month: month)

    LazyVGrid(columns: CalendarGridHelper.columns, spacing: Spacing.xxs) {
      ForEach(days, id: \.id) { dayInfo in
        let isToday = dayInfo.dateISO == todayISO()

        CalendarDayCell(
          dayInfo: dayInfo,
          style: cellStyle(isToday: isToday),
          content: cellContent(for: dayInfo)
        )
      }
    }
  }

  private func cellStyle(isToday: Bool) -> CalendarCellStyle {
    if isToday {
      return CalendarCellStyle(
        backgroundColor: Color.tidexBlue.opacity(0.2),
        borderColor: .clear,
        borderWidth: 0,
        dayNumberColor: .tidexBlue
      )
    }
    return .default
  }

  private func cellContent(for dayInfo: CalendarDayInfo) -> CalendarCellContent {
    guard let dateISO = dayInfo.dateISO else { return .empty }

    if let hoursData = hoursByDate[dateISO] {
      return .hours(hoursData)
    }

    return .empty
  }
}

// MARK: - Calendar Share Options Sheet

/// Bottom sheet for selecting calendar share options
struct CalendarShareOptionsSheet: View {
  let onShowEarnings: () -> Void
  let onHideEarnings: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: Spacing.mlg) {
      // Title
      Text(.shiftsShareTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
        .padding(.top, Spacing.md)

      VStack(spacing: Spacing.sm) {
        // Show earnings option
        Button {
          onShowEarnings()
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "eye")
              .font(.system(size: 20, weight: .medium))
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(.shiftsShareShowEarnings)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)

        // Hide earnings option
        Button {
          onHideEarnings()
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "eye.slash")
              .font(.system(size: 20, weight: .medium))
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(.shiftsShareHideEarnings)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Spacing.mlg)

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }
}

// MARK: - Image Rendering Extension

extension ShareableCalendarView {
  /// Renders the view as a PNG image using the current color scheme
  @MainActor
  func renderAsImage() -> UIImage? {
    let renderer = ImageRenderer(content: self)
    renderer.scale = 3.0  // High resolution for sharing
    return renderer.uiImage
  }
}
