import SwiftUI
import UIKit

// MARK: - Gesture State Machine

/// The current mode of the gesture state machine
private enum GestureMode: Equatable {
    /// No touch active
    case idle
    /// Long-press activated, actively selecting date range
    case selecting
}

// MARK: - Shifts Calendar View

/// Full-featured calendar for the Shifts tab
/// Shows shift times or earnings per day, ISO week numbers, and monthly totals
/// Supports multi-date selection via long-press + drag
struct ShiftsCalendarView: View {
    let shifts: [ShiftWithComputations]
    let month: Date
    let year: Int
    let monthNumber: Int  // 1-12
    let currency: String
    let showEarnings: Bool

    /// Transition phase for header text animations
    var phase: MonthTransitionPhase?

    // Day tap callback (single tap for selection toggle)
    var onDayTapped: ((String, [ShiftWithComputations]) -> Void)?

    // Selection state bindings from ViewModel
    @Binding var selectedDates: Set<String>

    /// Whether delete confirmation is active
    let confirmingDelete: Bool

    /// Whether deletion is in progress
    let isDeleting: Bool

    /// Selected earnings from ViewModel (computed across all months)
    let selectedEarnings: (net: Double, gross: Double)?

    /// Whether any selected shift has tax enabled
    let selectedHasTaxEnabled: Bool

    // Action callbacks
    var onDelete: (() -> Void)?
    var onConfirmDelete: (() -> Void)?
    var onCancelDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDetails: (() -> Void)?
    var onEdit: (() -> Void)?
    var onMove: (() -> Void)?
    var onClearSelection: (() -> Void)?

    // Range selection callback (for long-press + drag)
    var onSelectDateRange: (([String]) -> Void)?

    // Empty day tap callback (for navigating to add shift with date)
    var onEmptyDayTapped: ((_ dateISO: String?) -> Void)?

    // Copy/Move mode state
    let isCopyMode: Bool
    let isMoveMode: Bool
    let isCopying: Bool
    let isMoving: Bool

    // Copy/Move callbacks
    var onCopyToDate: ((String) -> Void)?
    var onMoveToDate: ((String) -> Void)?
    var onCancelCopyMove: (() -> Void)?

    // Selection mode toggle - when enabled, taps/long-press work; when disabled, swipes work
    @Binding var isSelectionModeEnabled: Bool

    // Newly added dates for celebration highlighting
    var newlyAddedDates: Set<String> = []

    // Date to highlight from widget deeplink (temporary visual highlight)
    var deepLinkHighlightDate: String?

    @Environment(\.localization) private var localization
    @State private var viewMode: CalendarViewMode = CalendarViewMode.load()

    // MARK: - Gesture State

    /// Current gesture state
    @State private var gestureMode: GestureMode = .idle

    /// ISO date where long-press started (anchor for range)
    @State private var anchorDateISO: String?

    /// Current hover date during drag
    @State private var hoverDateISO: String?

    /// Preview dates during drag (before committing)
    @State private var dragPreviewDates: Set<String> = []

    /// Track the last displayed earnings amount for smooth animation
    @State private var lastDisplayedEarnings: Double = 0

    /// Track the last displayed gross earnings amount for smooth animation
    @State private var lastDisplayedGrossEarnings: Double = 0

    // Haptic feedback for UI interactions (non-gesture haptics)
    private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)
    private let warningHaptic = UINotificationFeedbackGenerator()

    private let calendar = Calendar.current

    // MARK: - Computed Data

    /// Earnings by ISO date string
    private var earningsByDate: [String: Double] {
        var result: [String: Double] = [:]
        for shift in shifts {
            let net = shift.taxEnabled ? shift.netPay : shift.grossPay
            result[shift.shiftDate, default: 0] += net
        }
        return result
    }

    /// Hours by ISO date string
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

    /// Monthly totals (net and gross)
    private var monthlyTotals: (net: Double, gross: Double) {
        let filteredShifts = shifts.filter { shift in
            guard let date = Date.fromISODateString(shift.shiftDate) else { return false }
            let components = calendar.dateComponents([.year, .month], from: date)
            return components.year == year && components.month == monthNumber
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
        VStack(spacing: 0) {
            // Header: Month name + Year and Total
            headerRow

            // Weekday headers
            CalendarWeekdayHeader()
                .padding(.bottom, 8)

            // Calendar grid with gesture handling
            calendarGrid
                .padding(.bottom, 12)

            // Action bar (view mode toggle or selection actions)
            actionBar
        }
    }

    // MARK: - Header Row

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            // Month name + Year (or selection count)
            // Animated horizontally on month change (like the month picker)
            HStack(spacing: 6) {
                Text(monthName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                // Show selection count or year
                if selectedDates.count >= 2 {
                    Text("(\(selectedDates.count))")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.tidexTextMuted)
                } else {
                    Text(String(year))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.tidexTextMuted)
                }
            }
            .modifier(HeaderTextTransitionModifier(phase: phase))

            Spacer()

            // Monthly total or selection total (if showing earnings)
            if showEarnings {
                earningsDisplay
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    // MARK: - Header Text Transition

    /// Applies horizontal slide transition to the month/year header text
    private struct HeaderTextTransitionModifier: ViewModifier {
        let phase: MonthTransitionPhase?

        func body(content: Content) -> some View {
            if let phase = phase {
                content
                    .id("header-\(phase.id)")
                    .transition(textTransition(for: phase))
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.85),
                        value: phase.id
                    )
            } else {
                content
            }
        }

        private func textTransition(for phase: MonthTransitionPhase) -> AnyTransition {
            let offset: CGFloat = phase.direction == .next ? 20 : -20
            return .asymmetric(
                insertion: .offset(x: offset).combined(with: .opacity),
                removal: .offset(x: -offset).combined(with: .opacity)
            )
        }
    }

    /// Earnings display - shows monthly or selection totals
    @ViewBuilder
    private var earningsDisplay: some View {
        // Use selection earnings if dates are selected, otherwise monthly
        let displayTotals: (net: Double, gross: Double) = {
            if selectedDates.isEmpty {
                return monthlyTotals
            } else if let selected = selectedEarnings {
                return selected
            } else {
                return monthlyTotals
            }
        }()

        // Use selectedHasTaxEnabled when dates are selected
        let showTax = selectedDates.isEmpty ? hasTaxEnabled : selectedHasTaxEnabled
        let displayAmount = showTax ? displayTotals.net : displayTotals.gross

        VStack(alignment: .trailing, spacing: 2) {
            if displayTotals.gross == 0 {
                Text("—")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
            } else {
                CurrencyCountUpText(
                    amount: displayAmount,
                    animateOnAppear: false,
                    animateFrom: lastDisplayedEarnings > 0 ? lastDisplayedEarnings : nil
                )
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
                .onChange(of: displayAmount) { _, newValue in
                    lastDisplayedEarnings = newValue
                }
                .onAppear {
                    if lastDisplayedEarnings == 0 {
                        lastDisplayedEarnings = displayAmount
                    }
                }
            }

            if showTax && displayTotals.gross > 0 {
                CurrencyCountUpText(
                    amount: displayTotals.gross,
                    animateOnAppear: false,
                    animateFrom: lastDisplayedGrossEarnings > 0 ? lastDisplayedGrossEarnings : nil
                )
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
                .onChange(of: displayTotals.gross) { _, newValue in
                    lastDisplayedGrossEarnings = newValue
                }
                .onAppear {
                    if lastDisplayedGrossEarnings == 0 {
                        lastDisplayedGrossEarnings = displayTotals.gross
                    }
                }
            }
        }
    }

    // MARK: - Month Name

    private var monthName: String {
        CalendarGridHelper.monthName(
            from: month,
            locale: Locale(identifier: localization.currentLocale.localeIdentifier)
        )
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private var calendarGrid: some View {
        let days = CalendarGridHelper.daysInMonth(year: year, month: monthNumber)

        LazyVGrid(columns: CalendarGridHelper.columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []
                let isSelected = dayInfo.dateISO.map { selectedDates.contains($0) } ?? false
                let isInDragPreview = dayInfo.dateISO.map { dragPreviewDates.contains($0) } ?? false
                let isNewlyAdded = dayInfo.dateISO.map { newlyAddedDates.contains($0) } ?? false
                let isDeepLinkHighlighted = dayInfo.dateISO == deepLinkHighlightDate
                let isToday = dayInfo.dateISO == todayISO()

                CalendarDayCell(
                    dayInfo: dayInfo,
                    style: cellStyle(
                        isToday: isToday,
                        isSelected: isSelected,
                        isInDragPreview: isInDragPreview,
                        isNewlyAdded: isNewlyAdded,
                        isDeepLinkHighlighted: isDeepLinkHighlighted
                    ),
                    content: cellContent(
                        for: dayInfo,
                        hasShifts: !shiftsOnDay.isEmpty
                    )
                )
            }
        }
        .coordinateSpace(name: "calendar")
        .overlay(
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .calendarTapGesture(
                        onTap: { location in
                            handleTap(at: location, geometry: geometry, days: days)
                        },
                        isEnabled: !isSelectionModeEnabled
                    )
                    .calendarSelectionGestures(
                        actions: CalendarGestureActions(
                            onTap: { location in
                                handleTap(at: location, geometry: geometry, days: days)
                            },
                            onDragStart: { location in
                                handleDragStart(at: location, geometry: geometry, days: days)
                            },
                            onDragChanged: { location in
                                handleDragChanged(at: location, geometry: geometry, days: days)
                            },
                            onDragEnded: {
                                handleDragEnded()
                            }
                        ),
                        config: .default,
                        isEnabled: isSelectionModeEnabled
                    )
            }
        )
    }

    // MARK: - Cell Styling

    /// Celebration green color for newly added shifts
    private static let celebrationColor = Color(red: 0.298, green: 0.686, blue: 0.314)

    /// Purple/violet color for deep link highlight from widgets
    private static let deepLinkHighlightColor = Color(red: 0.545, green: 0.361, blue: 0.965)

    private func cellStyle(
        isToday: Bool,
        isSelected: Bool,
        isInDragPreview: Bool,
        isNewlyAdded: Bool,
        isDeepLinkHighlighted: Bool
    ) -> CalendarCellStyle {
        // Priority order: deep link > newly added > selected/drag > today > default
        if isDeepLinkHighlighted {
            return CalendarCellStyle(
                backgroundColor: Self.deepLinkHighlightColor.opacity(0.2),
                borderColor: Self.deepLinkHighlightColor,
                borderWidth: 2.5,
                dayNumberColor: .tidexTextPrimary
            )
        }
        if isNewlyAdded {
            return CalendarCellStyle(
                backgroundColor: Self.celebrationColor.opacity(0.2),
                borderColor: Self.celebrationColor,
                borderWidth: 2.5,
                dayNumberColor: .tidexTextPrimary
            )
        }
        if isSelected || isInDragPreview {
            return CalendarCellStyle(
                backgroundColor: Color.tidexBlue.opacity(0.15),
                borderColor: .tidexBlue,
                borderWidth: 2,
                dayNumberColor: .tidexTextPrimary
            )
        }
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

    private func cellContent(for dayInfo: CalendarDayInfo, hasShifts: Bool) -> CalendarCellContent {
        guard let dateISO = dayInfo.dateISO else { return .empty }

        let effectiveViewMode = showEarnings ? viewMode : .hours

        if effectiveViewMode == .money, let amount = earningsByDate[dateISO] {
            return .earnings(amount)
        } else if effectiveViewMode == .hours, let hoursData = hoursByDate[dateISO] {
            return .hours(hoursData)
        }

        return .empty
    }

    // MARK: - Gesture Handling

    private func handleTap(at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]) {
        guard let dayISO = findDayAt(location: location, geometry: geometry, days: days) else {
            if isCopyMode || isMoveMode {
                onCancelCopyMove?()
            } else {
                onEmptyDayTapped?(nil)
            }
            return
        }

        if isCopyMode {
            onCopyToDate?(dayISO)
            return
        }

        if isMoveMode {
            onMoveToDate?(dayISO)
            return
        }

        let shiftsOnDay = shiftsByDate[dayISO] ?? []

        if shiftsOnDay.isEmpty {
            onEmptyDayTapped?(dayISO)
        } else {
            onDayTapped?(dayISO, shiftsOnDay)
        }
    }

    private func handleDragStart(at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]) {
        guard let dayISO = findDayAt(location: location, geometry: geometry, days: days) else {
            return
        }

        gestureMode = .selecting
        anchorDateISO = dayISO
        hoverDateISO = dayISO
        dragPreviewDates = [dayISO]
    }

    private func handleDragChanged(at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]) {
        guard gestureMode == .selecting else { return }

        if let dayISO = findDayAt(location: location, geometry: geometry, days: days) {
            if dayISO != hoverDateISO {
                hoverDateISO = dayISO
                updateDragPreview()
            }
        }
    }

    private func handleDragEnded() {
        guard gestureMode == .selecting else {
            resetGestureState()
            return
        }

        if !dragPreviewDates.isEmpty {
            let datesToSelect = Array(dragPreviewDates)
            onSelectDateRange?(datesToSelect)
        }

        resetGestureState()
    }

    private func resetGestureState() {
        gestureMode = .idle
        anchorDateISO = nil
        hoverDateISO = nil
        dragPreviewDates.removeAll()
    }

    private func updateDragPreview() {
        guard let anchorISO = anchorDateISO, let hoverISO = hoverDateISO else {
            dragPreviewDates.removeAll()
            return
        }

        let range = buildDateRange(from: anchorISO, to: hoverISO)
        let datesWithShifts = range.filter { dateISO in
            if let shiftsOnDay = shiftsByDate[dateISO] {
                return !shiftsOnDay.isEmpty
            }
            return false
        }

        dragPreviewDates = Set(datesWithShifts)
    }

    private func buildDateRange(from startISO: String, to endISO: String) -> [String] {
        guard let startDate = Date.fromISODateString(startISO),
              let endDate = Date.fromISODateString(endISO) else {
            return [startISO]
        }

        let (earlierDate, laterDate) = startDate <= endDate ? (startDate, endDate) : (endDate, startDate)

        var result: [String] = []
        var current = earlierDate

        while current <= laterDate {
            result.append(current.toISODateString())
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }

        return result
    }

    private func findDayAt(location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]) -> String? {
        let gridWidth = geometry.size.width
        let gridHeight = geometry.size.height

        let numRows = (days.count + 6) / 7
        let cellWidth = gridWidth / 7
        let cellHeight = gridHeight / CGFloat(numRows)

        let col = Int(location.x / cellWidth)
        let row = Int(location.y / cellHeight)

        guard col >= 0, col < 7, row >= 0, row < numRows else { return nil }

        let index = row * 7 + col
        guard index >= 0, index < days.count else { return nil }

        let dayInfo = days[index]
        guard !dayInfo.isOutsideMonth else { return nil }

        return dayInfo.dateISO
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 0) {
            if isCopyMode || isMoveMode {
                copyMoveBar
            } else if selectedDates.isEmpty {
                CalendarViewModeToggle(
                    viewMode: $viewMode,
                    currency: currency,
                    showMoneyOption: showEarnings
                )
            } else if selectedDates.count == 1 {
                singleSelectionBar
            } else {
                multiSelectionBar
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedDates.count)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: confirmingDelete)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isCopyMode)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isMoveMode)
        .onAppear {
            toggleHaptic.prepare()
            warningHaptic.prepare()
        }
    }

    @ViewBuilder
    private var copyMoveBar: some View {
        HStack(spacing: 4) {
            if isCopying || isMoving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: isCopyMode ? .tidexBlue : .orange))
                    .scaleEffect(0.8)
                    .frame(width: 36, height: 36)

                Text(isCopyMode
                    ? localization.string("shifts.copying")
                    : localization.string("shifts.moving"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                    .frame(maxWidth: .infinity)
            } else {
                Image(systemName: isCopyMode ? "doc.on.doc" : "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isCopyMode ? .tidexBlue : .orange)
                    .frame(width: 36, height: 36)

                Text(isCopyMode
                    ? localization.string("shifts.selectCopyTarget")
                    : localization.string("shifts.selectMoveTarget"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                    .frame(maxWidth: .infinity)
            }

            Button {
                toggleHaptic.impactOccurred()
                onCancelCopyMove?()
            } label: {
                Text(localization.string("common.cancel"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, Spacing.sm)
                    .background(Capsule().fill(Color.tidexBrandPrimary))
            }
            .buttonStyle(.plain)
            .disabled(isCopying || isMoving)
        }
        .frame(height: 36)
        .padding(4)
        .background(Capsule().fill(Color.tidexSurfaceSecondary))
    }

    @ViewBuilder
    private var singleSelectionBar: some View {
        HStack(spacing: 4) {
            deleteButton

            if !confirmingDelete {
                Button {
                    toggleHaptic.impactOccurred()
                    onCopy?()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexBlue)
                        .frame(width: 44, height: 36)
                        .background(Capsule().fill(Color.tidexBlue.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }

            if confirmingDelete {
                cancelButton
            } else {
                Button {
                    toggleHaptic.impactOccurred()
                    onEdit?()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexBlue)
                        .frame(width: 44, height: 36)
                        .background(Capsule().fill(Color.tidexBlue.opacity(0.1)))
                }
                .buttonStyle(.plain)

                Button {
                    toggleHaptic.impactOccurred()
                    onDetails?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                        Text(localization.string("shifts.details"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Capsule().fill(Color.tidexBrandPrimary))
                }
                .buttonStyle(.plain)

                Button {
                    toggleHaptic.impactOccurred()
                    onMove?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .medium))
                        Text(localization.string("shifts.move"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Capsule().fill(Color.orange.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
        .padding(4)
        .background(Capsule().fill(Color.tidexSurfaceSecondary))
    }

    @ViewBuilder
    private var multiSelectionBar: some View {
        HStack(spacing: 4) {
            deleteButton

            if confirmingDelete {
                cancelButton
            } else {
                Button {
                    toggleHaptic.impactOccurred()
                    onClearSelection?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                        Text(localization.string("common.cancel"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.tidexTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Capsule().fill(Color.tidexSurfaceSecondary.opacity(0.8)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
        .padding(4)
        .background(Capsule().fill(Color.tidexSurfaceSecondary))
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button {
            if confirmingDelete {
                warningHaptic.notificationOccurred(.warning)
                onConfirmDelete?()
            } else {
                toggleHaptic.impactOccurred()
                onDelete?()
            }
        } label: {
            HStack(spacing: 6) {
                if isDeleting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: confirmingDelete ? .white : .red))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                }

                if confirmingDelete {
                    Text(localization.string("shifts.confirm"))
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundColor(confirmingDelete ? .white : .red)
            .frame(width: confirmingDelete ? nil : 44)
            .frame(maxWidth: confirmingDelete ? .infinity : nil, maxHeight: .infinity)
            .padding(.horizontal, confirmingDelete ? 16 : 0)
            .background(Capsule().fill(confirmingDelete ? Color.red : Color.red.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button {
            toggleHaptic.impactOccurred()
            onCancelDelete?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                Text(localization.string("common.cancel"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color.tidexBrandPrimary))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedDates: Set<String> = []
        @State private var isSelectionModeEnabled: Bool = false

        var body: some View {
            ScrollView {
                ShiftsCalendarView(
                    shifts: [],
                    month: Date(),
                    year: 2025,
                    monthNumber: 1,
                    currency: "kr",
                    showEarnings: true,
                    selectedDates: $selectedDates,
                    confirmingDelete: false,
                    isDeleting: false,
                    selectedEarnings: nil,
                    selectedHasTaxEnabled: false,
                    isCopyMode: false,
                    isMoveMode: false,
                    isCopying: false,
                    isMoving: false,
                    isSelectionModeEnabled: $isSelectionModeEnabled,
                    newlyAddedDates: []
                )
                .padding()
            }
            .background(Color.tidexBackground)
            .environment(\.localization, LocalizationManager.shared)
        }
    }

    return PreviewWrapper()
}
