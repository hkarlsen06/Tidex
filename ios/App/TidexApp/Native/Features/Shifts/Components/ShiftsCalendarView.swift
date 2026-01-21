import SwiftUI
import UIKit

// MARK: - Calendar View Mode

/// Mode for displaying data in calendar cells
enum CalendarViewMode: String, CaseIterable {
    case hours
    case money

    /// UserDefaults key for persisting view mode
    static let userDefaultsKey = "shifts_calendar_view_mode"

    /// Save the current mode to UserDefaults
    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }

    /// Load saved mode from UserDefaults (defaults to hours)
    static func load() -> CalendarViewMode {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let mode = CalendarViewMode(rawValue: rawValue) else {
            return .hours
        }
        return mode
    }
}

// MARK: - Hours Data for Calendar Cell

/// Time range data for a single day
struct HoursData: Equatable {
    let start: String
    let end: String
    let crossesMidnight: Bool
}

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

    // Haptic feedback for UI interactions (non-gesture haptics)
    private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)
    private let warningHaptic = UINotificationFeedbackGenerator()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

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
        var shiftsByDate: [String: [ShiftWithComputations]] = [:]

        for shift in shifts {
            shiftsByDate[shift.shiftDate, default: []].append(shift)
        }

        var result: [String: HoursData] = [:]

        for (date, shiftsOnDate) in shiftsByDate {
            // Sort by start time
            let sorted = shiftsOnDate.sorted { $0.startTime < $1.startTime }

            let earliestStart = sorted.first?.startTime ?? ""
            let latestEnd = sorted.map(\.endTime).max() ?? ""

            // Check if any shift crosses midnight
            let crossesMidnight = shiftsOnDate.contains { shift in
                let startMinutes = timeToMinutes(shift.startTime)
                let endMinutes = timeToMinutes(shift.endTime)
                return endMinutes <= startMinutes
            }

            result[date] = HoursData(
                start: formatTime(earliestStart),
                end: formatTime(latestEnd),
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
            weekdayHeaderRow
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

            Spacer()

            // Monthly total or selection total (if showing earnings)
            if showEarnings {
                earningsDisplay
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
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
                    // Track the displayed amount for animating FROM on view recreation
                    lastDisplayedEarnings = newValue
                }
                .onAppear {
                    // Initialize on first appear
                    if lastDisplayedEarnings == 0 {
                        lastDisplayedEarnings = displayAmount
                    }
                }
            }

            if showTax && displayTotals.gross > 0 {
                Text(formatCurrency(displayTotals.gross))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
            }
        }
    }

    // MARK: - Month Name

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: localization.currentLocale.localeIdentifier)
        return formatter.string(from: month).capitalized
    }

    // MARK: - Weekday Header Row

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let isNorwegian = localization.currentLocale == .norwegian
        if isNorwegian {
            return ["MA", "TI", "ON", "TO", "FR", "LØ", "SØ"]
        } else {
            return ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
        }
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private var calendarGrid: some View {
        let days = daysInMonth()

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []
                let isInDragPreview = dayInfo.dateISO.map { dragPreviewDates.contains($0) } ?? false
                let isNewlyAdded = dayInfo.dateISO.map { newlyAddedDates.contains($0) } ?? false
                let isDeepLinkHighlighted = dayInfo.dateISO == deepLinkHighlightDate

                ShiftsCalendarDayCell(
                    dayInfo: dayInfo,
                    viewMode: showEarnings ? viewMode : .hours,
                    earnings: dayInfo.dateISO.flatMap { earningsByDate[$0] },
                    hours: dayInfo.dateISO.flatMap { hoursByDate[$0] },
                    isToday: dayInfo.dateISO == todayISO(),
                    hasShifts: !shiftsOnDay.isEmpty,
                    isSelected: dayInfo.isSelected,
                    isInDragPreview: isInDragPreview,
                    isNewlyAdded: isNewlyAdded,
                    isDeepLinkHighlighted: isDeepLinkHighlighted
                )
            }
        }
        .coordinateSpace(name: "calendar")
        // Gesture handling depends on selection mode:
        // - Normal mode: tap to select (swipes pass through to parent)
        // - Selection mode: tap + drag for range selection
        .overlay(
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    // Normal mode: just tap gestures (swipes work)
                    .calendarTapGesture(
                        onTap: { location in
                            handleTap(at: location, geometry: geometry, days: days)
                        },
                        isEnabled: !isSelectionModeEnabled
                    )
                    // Selection mode: tap + drag gestures
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

    // MARK: - Gesture Handling

    /// Handle tap gesture
    private func handleTap(at location: CGPoint, geometry: GeometryProxy, days: [DayInfo]) {
        guard let dayISO = findDayAt(location: location, geometry: geometry, days: days) else {
            // Tapped outside valid days
            if isCopyMode || isMoveMode {
                // In copy/move mode, tapping outside cancels
                onCancelCopyMove?()
            } else {
                onEmptyDayTapped?(nil)
            }
            return
        }

        // Handle copy/move mode - any date tap triggers the operation
        if isCopyMode {
            onCopyToDate?(dayISO)
            return
        }

        if isMoveMode {
            onMoveToDate?(dayISO)
            return
        }

        // Normal mode
        let shiftsOnDay = shiftsByDate[dayISO] ?? []

        if shiftsOnDay.isEmpty {
            // Tapped empty day - pass the date for pre-selection in Add tab
            onEmptyDayTapped?(dayISO)
        } else {
            // Tapped day with shifts
            onDayTapped?(dayISO, shiftsOnDay)
        }
    }

    /// Handle drag start (beginning of range selection)
    private func handleDragStart(at location: CGPoint, geometry: GeometryProxy, days: [DayInfo]) {
        guard let dayISO = findDayAt(location: location, geometry: geometry, days: days) else {
            return
        }

        // Enter selecting mode - anchor on the day where drag started
        gestureMode = .selecting
        anchorDateISO = dayISO
        hoverDateISO = dayISO
        dragPreviewDates = [dayISO]
    }

    /// Handle drag movement (extending range selection)
    private func handleDragChanged(at location: CGPoint, geometry: GeometryProxy, days: [DayInfo]) {
        guard gestureMode == .selecting else { return }

        // Update hover date and preview
        if let dayISO = findDayAt(location: location, geometry: geometry, days: days) {
            if dayISO != hoverDateISO {
                hoverDateISO = dayISO
                updateDragPreview()
            }
        }
    }

    /// Handle drag end
    private func handleDragEnded() {
        guard gestureMode == .selecting else {
            resetGestureState()
            return
        }

        // Commit the drag preview selection
        if !dragPreviewDates.isEmpty {
            let datesToSelect = Array(dragPreviewDates)
            onSelectDateRange?(datesToSelect)
        }

        resetGestureState()
    }

    /// Reset all gesture state
    private func resetGestureState() {
        gestureMode = .idle
        anchorDateISO = nil
        hoverDateISO = nil
        dragPreviewDates.removeAll()
    }

    /// Update drag preview dates based on anchor and hover
    private func updateDragPreview() {
        guard let anchorISO = anchorDateISO, let hoverISO = hoverDateISO else {
            dragPreviewDates.removeAll()
            return
        }

        // Build date range from anchor to hover
        let range = buildDateRange(from: anchorISO, to: hoverISO)

        // Filter to only dates with shifts
        let datesWithShifts = range.filter { dateISO in
            if let shiftsOnDay = shiftsByDate[dateISO] {
                return !shiftsOnDay.isEmpty
            }
            return false
        }

        dragPreviewDates = Set(datesWithShifts)
    }

    /// Build contiguous date range between two ISO dates
    private func buildDateRange(from startISO: String, to endISO: String) -> [String] {
        guard let startDate = Date.fromISODateString(startISO),
              let endDate = Date.fromISODateString(endISO) else {
            return [startISO]
        }

        // Determine direction
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

    /// Find the day at a given location in the calendar grid
    private func findDayAt(location: CGPoint, geometry: GeometryProxy, days: [DayInfo]) -> String? {
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
                // Copy/Move mode: show instruction bar
                copyMoveBar
            } else if selectedDates.isEmpty {
                // Default: Hours/Money toggle
                viewModeToggleContent
            } else if selectedDates.count == 1 {
                // Single selection: Delete | Copy | Details | Move
                singleSelectionBar
            } else {
                // Multi selection: Delete | Cancel
                multiSelectionBar
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.tidexSurfaceSecondary))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedDates.count)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: confirmingDelete)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isCopyMode)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isMoveMode)
        .onAppear {
            toggleHaptic.prepare()
            warningHaptic.prepare()
        }
    }

    /// Action bar shown when in copy or move mode
    @ViewBuilder
    private var copyMoveBar: some View {
        HStack(spacing: 4) {
            // Loading indicator or instruction text
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
                // Icon indicating mode
                Image(systemName: isCopyMode ? "doc.on.doc" : "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isCopyMode ? .tidexBlue : .orange)
                    .frame(width: 36, height: 36)

                // Instruction text
                Text(isCopyMode
                    ? localization.string("shifts.selectCopyTarget")
                    : localization.string("shifts.selectMoveTarget"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                    .frame(maxWidth: .infinity)
            }

            // Cancel button
            Button {
                toggleHaptic.impactOccurred()
                onCancelCopyMove?()
            } label: {
                Text(localization.string("common.cancel"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.tidexBrandPrimary))
            }
            .buttonStyle(.plain)
            .disabled(isCopying || isMoving)
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var singleSelectionBar: some View {
        HStack(spacing: 4) {
            // Delete button (expands on confirm)
            deleteButton

            if !confirmingDelete {
                // Copy button
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

            // Details/Cancel button
            if confirmingDelete {
                cancelButton
            } else {
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.tidexBrandPrimary))
                }
                .buttonStyle(.plain)
            }

            if !confirmingDelete {
                // Edit button (icon only)
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

                // Move button
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.orange.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var multiSelectionBar: some View {
        HStack(spacing: 4) {
            // Delete button
            deleteButton

            // Cancel/Close button
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.tidexSurfaceSecondary.opacity(0.8)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
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
            .frame(maxWidth: confirmingDelete ? .infinity : nil)
            .padding(.vertical, 10)
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.tidexBrandPrimary))
        }
        .buttonStyle(.plain)
    }

    /// Hours/Money toggle content
    @ViewBuilder
    private var viewModeToggleContent: some View {
        // Hours button
        Button {
            guard viewMode != .hours else { return }
            toggleHaptic.impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewMode = .hours
                viewMode.save()
            }
        } label: {
            HStack(spacing: 6) {
                Text("--:--")
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .medium))
            }
            .font(.system(size: 14, weight: viewMode == .hours ? .semibold : .regular))
            .foregroundColor(viewMode == .hours ? .tidexTextPrimary : .tidexTextMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
Group {
                    if viewMode == .hours {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular.interactive())
                    }
                }
            )
        }
        .buttonStyle(.plain)

        // Money button (only if showing earnings)
        if showEarnings {
            Button {
                guard viewMode != .money else { return }
                toggleHaptic.impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewMode = .money
                    viewMode.save()
                }
            } label: {
                Text("---- \(currency)")
                    .font(.system(size: 14, weight: viewMode == .money ? .semibold : .regular))
                    .foregroundColor(viewMode == .money ? .tidexTextPrimary : .tidexTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
Group {
                            if viewMode == .money {
                                Capsule()
                                    .fill(.clear)
                                    .glassEffect(.regular.interactive())
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Calendar Helpers

    struct DayInfo: Identifiable {
        let id: Int
        let dayNumber: Int
        let dateISO: String?
        let weekNumber: Int?  // ISO week number (only on Mondays)
        let isOutsideMonth: Bool
        let isSelected: Bool  // Whether this date is in selectedDates
    }

    private func daysInMonth() -> [DayInfo] {
        var days: [DayInfo] = []

        // Get first day of month
        var components = DateComponents()
        components.year = year
        components.month = monthNumber
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components) else { return days }

        // Get weekday of first day (1 = Sunday, 7 = Saturday)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        // Convert to Monday-start (0 = Monday, 6 = Sunday)
        let startOffset = (firstWeekday + 5) % 7

        // Get number of days in month
        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }

        // Get last day of previous month for "outside days"
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth)!
        let daysInPreviousMonth = calendar.range(of: .day, in: .month, for: previousMonth)!.count

        // Add days from previous month (outside days)
        for i in 0..<startOffset {
            let day = daysInPreviousMonth - startOffset + i + 1
            let date = calendar.date(byAdding: .day, value: i - startOffset, to: firstOfMonth)!
            let dateISO = date.toISODateString()
            let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil
            let isSelected = selectedDates.contains(dateISO)

            days.append(DayInfo(
                id: -1000 + i,
                dayNumber: day,
                dateISO: dateISO,
                weekNumber: weekNum,
                isOutsideMonth: true,
                isSelected: isSelected
            ))
        }

        // Add cells for each day in current month
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let dateISO = date.toISODateString()
            let isMonday = calendar.component(.weekday, from: date) == 2
            let weekNum = isMonday ? getIsoWeek(from: date) : nil
            let isSelected = selectedDates.contains(dateISO)

            days.append(DayInfo(
                id: day,
                dayNumber: day,
                dateISO: dateISO,
                weekNumber: weekNum,
                isOutsideMonth: false,
                isSelected: isSelected
            ))
        }

        // Add days from next month to fill the last row
        let totalDays = days.count
        let remainder = totalDays % 7
        if remainder > 0 {
            let daysToAdd = 7 - remainder
            for i in 0..<daysToAdd {
                let date = calendar.date(byAdding: .day, value: range.count + i, to: firstOfMonth)!
                let dateISO = date.toISODateString()
                let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil
                let isSelected = selectedDates.contains(dateISO)

                days.append(DayInfo(
                    id: 1000 + i,
                    dayNumber: i + 1,
                    dateISO: dateISO,
                    weekNumber: weekNum,
                    isOutsideMonth: true,
                    isSelected: isSelected
                ))
            }
        }

        return days
    }

    private func getIsoWeek(from date: Date) -> Int {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.firstWeekday = 2  // Monday
        isoCalendar.minimumDaysInFirstWeek = 4
        return isoCalendar.component(.weekOfYear, from: date)
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }

    private func formatTime(_ time: String) -> String {
        // Remove seconds and leading zero (e.g., "08:30:00" -> "8:30")
        let hhmm = String(time.prefix(5))
        return hhmm.hasPrefix("0") ? String(hhmm.dropFirst()) : hhmm
    }

    private func timeToMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return 0 }
        return hours * 60 + minutes
    }
}

// MARK: - Shifts Calendar Day Cell

private struct ShiftsCalendarDayCell: View {
    let dayInfo: ShiftsCalendarView.DayInfo
    let viewMode: CalendarViewMode
    let earnings: Double?
    let hours: HoursData?
    let isToday: Bool
    let hasShifts: Bool
    let isSelected: Bool
    let isInDragPreview: Bool
    let isNewlyAdded: Bool
    let isDeepLinkHighlighted: Bool

    private var hasShift: Bool {
        earnings != nil || hours != nil
    }

    /// Whether this cell is tappable (has shifts and is in current month)
    private var isTappable: Bool {
        hasShifts && !dayInfo.isOutsideMonth
    }

    var body: some View {
        ZStack {
            // Week number (top-left corner, only on Mondays)
            if let weekNum = dayInfo.weekNumber {
                VStack {
                    HStack {
                        Text("\(weekNum)")
                            .font(.system(size: 9))
                            .foregroundColor(.tidexTextMuted)
                            .padding(.leading, 6)
                            .padding(.top, 4)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(dayNumberColor)
                        .padding(.trailing, 4)
                        .padding(.top, 3)
                }
                Spacer()
            }

            // Content (centered - hours or earnings)
            if viewMode == .money, let amount = earnings {
                Text(formatCompactCurrency(amount))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 8)
            } else if viewMode == .hours, let hoursData = hours {
                VStack(spacing: 1) {
                    Text(hoursData.start)
                        .font(.system(size: 14, weight: .bold))
                    Text(hoursData.end + (hoursData.crossesMidnight ? "*" : ""))
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.tidexTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1 / 1.3, contentMode: .fill)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            // Selection/today indicator ring
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .opacity(dayInfo.isOutsideMonth ? 0.4 : 1.0)
    }

    /// Celebration green color for newly added shifts
    private static let celebrationColor = Color(red: 0.298, green: 0.686, blue: 0.314)  // #4CAF50 Green

    /// Purple/violet color for deep link highlight from widgets
    private static let deepLinkHighlightColor = Color(red: 0.545, green: 0.361, blue: 0.965)  // #8B5CF5 Violet

    private var backgroundColor: Color {
        if isDeepLinkHighlighted {
            return Self.deepLinkHighlightColor.opacity(0.2)
        }
        if isNewlyAdded {
            return Self.celebrationColor.opacity(0.2)
        }
        if isSelected || isInDragPreview {
            return Color.tidexBlue.opacity(0.15)
        }
        if isToday {
            return Color.tidexBlue.opacity(0.2)
        }
        return Color.tidexSurfacePrimary
    }

    private var borderColor: Color {
        if isDeepLinkHighlighted {
            return Self.deepLinkHighlightColor
        }
        if isNewlyAdded {
            return Self.celebrationColor
        }
        if isSelected || isInDragPreview {
            return Color.tidexBlue
        }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        if isDeepLinkHighlighted {
            return 2.5
        }
        if isNewlyAdded {
            return 2.5
        }
        if isSelected || isInDragPreview {
            return 2
        }
        return 0
    }

    private var dayNumberColor: Color {
        if isToday {
            return .tidexBlue
        }
        if hasShift {
            return .white
        }
        return .tidexTextPrimary
    }

    private func formatCompactCurrency(_ amount: Double) -> String {
        // Compact format without currency symbol for calendar cells
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
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
