import SwiftUI

/// Sheet for editing a recurring shift pattern
/// Allows editing start/end times, repeat interval, selected days, and end condition
/// Uses the same UI layout as the add recurring shift flow
struct RecurringShiftEditorSheet: View {
    let recurringShift: RecurringShiftRow
    let onSave: ((RecurringShiftEditResult) -> Void)?
    let onDelete: (() -> Void)?

        @Environment(\.dismiss) private var dismiss

    // MARK: - Edit State

    @State private var editedStartTime: Date? = nil
    @State private var editedEndTime: Date? = nil
    @State private var editedRepeatInterval: Int = 0
    @State private var editedSelectedDays: SelectedDays = [:]
    @State private var editedEndCondition: EndCondition? = nil

    // MARK: - Calendar Display State

    @State private var displayMonth: Date = Date()
    @State private var navigationDirection: MonthNavigationDirection?

    // MARK: - UI State

    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var focusedTimeField: NumericTimeInput.TimeField?

    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Computed Properties

    /// Whether any changes have been made
    private var hasChanges: Bool {
        guard let startTime = editedStartTime, let endTime = editedEndTime else {
            return false
        }
        let newStartTime = formatTimeToString(startTime)
        let newEndTime = formatTimeToString(endTime)

        return newStartTime != recurringShift.cleanStartTime ||
               newEndTime != recurringShift.cleanEndTime ||
               editedRepeatInterval != recurringShift.repeat_interval_weeks ||
               editedSelectedDays != recurringShift.selected_days ||
               editedEndCondition != recurringShift.end_condition
    }

    /// Whether form is valid for saving
    private var canSave: Bool {
        editedStartTime != nil && editedEndTime != nil && !editedSelectedDays.isEmpty
    }

    // MARK: - Month Navigation

    /// Display year from display month
    private var displayYear: Int {
        Calendar.current.component(.year, from: displayMonth)
    }

    /// Display month number (1-12) from display month
    private var displayMonthNumber: Int {
        Calendar.current.component(.month, from: displayMonth)
    }

    /// Localized month name
    private var displayMonthName: String {
        CalendarGridHelper.monthName(
            from: displayMonth,
            locale: Locale(identifier: Locale.current.identifier)
        )
    }

    /// Month transition phase for animations
    private var monthPhase: MonthTransitionPhase {
        MonthTransitionPhase(
            year: displayYear,
            month: displayMonthNumber,
            direction: navigationDirection
        )
    }

    /// Navigate to previous month
    private func goToPreviousMonth() {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayMonth) else { return }
        navigationDirection = .previous
        displayMonth = newMonth
    }

    /// Navigate to next month
    private func goToNextMonth() {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayMonth) else { return }
        navigationDirection = .next
        displayMonth = newMonth
    }

    /// Navigate to a specific month
    private func navigateToMonth(year: Int, month: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return }

        // Determine direction for animation
        if date > displayMonth {
            navigationDirection = .next
        } else if date < displayMonth {
            navigationDirection = .previous
        }

        displayMonth = date
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let availableHeight = geometry.size.height - (MonthPickerLayout.height + MonthPickerLayout.bottomPadding)

                ScrollView {
                    VStack(spacing: 20) {
                        // Header with title and optional reset button
                        headerSection

                        // Duration picker (same as add flow)
                        DurationPicker(endCondition: $editedEndCondition)

                        // Repeat interval picker (same as add flow)
                        RepeatIntervalPicker(interval: $editedRepeatInterval)

                        // Time picker (same as add flow)
                        TimeRangePicker(
                            startTime: $editedStartTime,
                            endTime: $editedEndTime,
                            focusedFieldBinding: $focusedTimeField
                        )

                        Divider()
                            .background(Color.tidexBorder)

                        // Month navigation header
                        AnimatedMonthHeader(
                            monthName: displayMonthName,
                            year: displayYear,
                            phase: monthPhase,
                            config: .compact,
                            onPrevious: goToPreviousMonth,
                            onNext: goToNextMonth,
                            onNavigateToMonth: navigateToMonth,
                            isLoading: false
                        )

                        // Weekday chip bar showing selected anchors
                        WeekdayChipBar(
                            selectedDays: editedSelectedDays,
                            onRemove: { weekday in
                                // Don't allow removing the last weekday
                                if editedSelectedDays.count > 1 {
                                    editedSelectedDays.removeValue(forKey: weekday)
                                }
                            }
                        )

                        // Calendar for selecting anchor dates
                        EditRecurringCalendarView(
                            displayMonth: displayMonth,
                            selectedDays: $editedSelectedDays,
                            repeatInterval: editedRepeatInterval,
                            endCondition: editedEndCondition,
                            existingShiftDates: []
                        )

                        // Error message
                        if let error = errorMessage {
                            errorBanner(message: error)
                        }

                        // Action Buttons
                        actionButtons
                    }
                    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: availableHeight, alignment: .top)
                }
                .monthSwipeGesture(
                    onSwipeLeft: goToNextMonth,
                    onSwipeRight: goToPreviousMonth,
                    isEnabled: true
                )
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 16, for: .scrollContent)
            }
            .background(Color.tidexBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: .commonCancel)) {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: .commonSave)) {
                        saveChanges()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                    .disabled(isSaving || !hasChanges || !canSave)
                    .opacity(isSaving || !hasChanges || !canSave ? 0.5 : 1)
                }
            }
        }
        .onAppear {
            initializeEditState()
        }
        .interactiveDismissDisabled(hasChanges)
        .alert(
            String(localized: .recurringDeleteConfirmTitle),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: .commonCancel), role: .cancel) {}
            Button(String(localized: .recurringDeleteConfirmButton), role: .destructive) {
                deleteRecurringShift()
            }
        } message: {
            Text(.recurringDeleteConfirmMessage)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(.recurringEditTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(.addShiftHeaderSubtitle)
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
            }

            Spacer()

            // Delete button (replaces reset button from add flow)
            if onDelete != nil {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.tidexError)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var actionButtons: some View {
        // Save button only - delete is in header
        Button {
            saveChanges()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .medium))
                }
                Text(.commonSaveChanges)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(hasChanges && canSave ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
            .cornerRadius(12)
        }
        .disabled(isSaving || !hasChanges || !canSave)
        .padding(.top, 8)
        .padding(.bottom, 80)  // Extra bottom padding to clear the month picker
    }

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.tidexError)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.tidexError)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexError.opacity(0.1))
        )
    }

    // MARK: - Helpers

    private func initializeEditState() {
        // Parse start time
        editedStartTime = parseTimeToDate(recurringShift.cleanStartTime)

        // Parse end time
        editedEndTime = parseTimeToDate(recurringShift.cleanEndTime)

        // Set repeat interval
        editedRepeatInterval = recurringShift.repeat_interval_weeks

        // Set selected days
        editedSelectedDays = recurringShift.selected_days

        // Set end condition
        editedEndCondition = recurringShift.end_condition

        // Initialize display month to the earliest anchor date
        initializeDisplayMonth()
    }

    /// Initialize the display month to show the earliest anchor date
    private func initializeDisplayMonth() {
        let anchorDates = recurringShift.selected_days.values.sorted()
        guard let earliestAnchor = anchorDates.first,
              let anchorDate = Date.fromISODateString(earliestAnchor) else {
            // Default to current month if no anchors
            displayMonth = Date()
            return
        }

        // Set display month to the month containing the earliest anchor
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: anchorDate)
        components.day = 1
        displayMonth = calendar.date(from: components) ?? Date()
    }

    private func parseTimeToDate(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: String(timeString.prefix(5))) else { return nil }

        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = calendar.component(.hour, from: time)
        components.minute = calendar.component(.minute, from: time)
        return calendar.date(from: components)
    }

    private func formatTimeToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func saveChanges() {
        guard hasChanges, canSave,
              let startTime = editedStartTime,
              let endTime = editedEndTime else { return }

        isSaving = true
        impactHaptic.impactOccurred()
        errorMessage = nil

        let result = RecurringShiftEditResult(
            recurringId: recurringShift.id,
            startTime: formatTimeToString(startTime),
            endTime: formatTimeToString(endTime),
            repeatIntervalWeeks: editedRepeatInterval,
            selectedDays: editedSelectedDays,
            endCondition: editedEndCondition
        )

        onSave?(result)
        dismiss()
    }

    private func deleteRecurringShift() {
        isDeleting = true
        impactHaptic.impactOccurred()
        onDelete?()
        dismiss()
    }
}

// MARK: - Supporting Types

/// Result of editing a recurring shift
struct RecurringShiftEditResult {
    let recurringId: String
    let startTime: String          // HH:mm format
    let endTime: String            // HH:mm format
    let repeatIntervalWeeks: Int
    let selectedDays: SelectedDays
    let endCondition: EndCondition?
}

// MARK: - Preview

#Preview {
    RecurringShiftEditorSheet(
        recurringShift: RecurringShiftRow(
            id: "preview-1",
            user_id: "user-1",
            start_time: "08:00",
            end_time: "16:00",
            repeat_interval_weeks: 0,
            selected_days: ["1": "2025-01-20", "3": "2025-01-22", "5": "2025-01-24"],
            end_condition: .months(value: 6),
            exclusions: nil,
            date_specific_supplements: nil
        ),
        onSave: { result in
            print("Save: \(result)")
        },
        onDelete: {
            print("Delete")
        }
    )
}
