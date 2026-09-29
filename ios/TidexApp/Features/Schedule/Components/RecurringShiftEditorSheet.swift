import SwiftUI

/// Sheet for editing a recurring shift pattern
/// Sections run in the order people think about a shift: time, days, duration, excluded dates
struct RecurringShiftEditorSheet: View {
  let recurringShift: RecurringShiftRow
  let onSave: ((RecurringShiftEditResult) -> Void)?
  let onDelete: (() -> Void)?

  @Environment(\.dismiss) private var dismiss

  // MARK: - Edit State

  @State private var editedStartTime: Date?
  @State private var editedEndTime: Date?
  @State private var editedRepeatInterval: Int = 0
  @State private var editedSelectedDays: SelectedDays = [:]
  @State private var editedEndCondition: EndCondition?
  @State private var editedExclusions: [String] = []

  // MARK: - Calendar Display State

  @State private var displayMonth = Date()  // swiftlint:disable:this explicit_type_interface
  @State private var navigationDirection: MonthNavigationDirection?

  // MARK: - UI State

  @State private var isSaving = false
  @State private var showDeleteConfirmation = false
  @State private var focusedTimeField: TimeInputField?

  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

  // MARK: - Computed Properties

  /// Whether any changes have been made
  private var hasChanges: Bool {
    guard let startTime = editedStartTime, let endTime = editedEndTime else {
      return false
    }
    let newStartTime = ShiftTimeFieldFormat.storedTime(
      from: startTime, original: recurringShift.cleanStartTime)
    let newEndTime = ShiftTimeFieldFormat.storedTime(
      from: endTime, original: recurringShift.cleanEndTime)

    return newStartTime != recurringShift.cleanStartTime
      || newEndTime != recurringShift.cleanEndTime
      || editedRepeatInterval != recurringShift.repeat_interval_weeks
      || editedSelectedDays != recurringShift.selected_days
      || editedEndCondition != recurringShift.end_condition
      || normalizeExclusions(editedExclusions)
        != normalizeExclusions(recurringShift.effectiveExclusions)
  }

  /// Whether form is valid for saving
  private var canSave: Bool {
    editedStartTime != nil && editedEndTime != nil && !editedSelectedDays.isEmpty
  }

  // MARK: - Month Navigation

  /// Display year from display month
  private var displayYear: Int {
    Calendar.gregorianCurrent.component(.year, from: displayMonth)
  }

  /// Display month number (1-12) from display month
  private var displayMonthNumber: Int {
    Calendar.gregorianCurrent.component(.month, from: displayMonth)
  }

  /// Localized month name
  private var displayMonthName: String {
    CalendarGridHelper.monthName(
      from: displayMonth,
      locale: Locale.appLocale
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
    guard let newMonth = Calendar.gregorianCurrent.date(byAdding: .month, value: -1, to: displayMonth) else {
      return
    }
    navigationDirection = .previous
    displayMonth = newMonth
  }

  /// Navigate to next month
  private func goToNextMonth() {
    guard let newMonth = Calendar.gregorianCurrent.date(byAdding: .month, value: 1, to: displayMonth) else {
      return
    }
    navigationDirection = .next
    displayMonth = newMonth
  }

  /// Navigate to a specific month
  private func navigateToMonth(year: Int, month: Int) {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    guard let date = Calendar.gregorianCurrent.date(from: components) else { return }

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
        let availableHeight = geometry.size.height - (MonthPickerLayout.totalBottomInset)

        ScrollView {
          VStack(alignment: .leading, spacing: Spacing.xl) {
            section(.shiftsTimeSection) {
              TimeRangePicker(
                startTime: $editedStartTime,
                endTime: $editedEndTime,
                focusedFieldBinding: $focusedTimeField
              )
            }

            daysSection

            DurationPicker(endCondition: $editedEndCondition)

            // Exclusions can only be restored here, so the section is hidden for shifts without any.
            if !recurringShift.effectiveExclusions.isEmpty {
              exclusionsSection
            }

            if onDelete != nil {
              deleteButton
            }
          }
          .frame(maxWidth: AdaptiveMaxWidth.tabContent)
          .padding(.horizontal, Spacing.md)
          .padding(.top, Spacing.md)
          .padding(.bottom, Spacing.bottomScrollMargin)  // Clears the month picker
          .frame(maxWidth: .infinity)
          .frame(minHeight: availableHeight, alignment: .top)
        }
        .monthSwipeGesture(
          onSwipeLeft: goToNextMonth,
          onSwipeRight: goToPreviousMonth,
          isEnabled: true
        )
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(
          .bottom, MonthPickerLayout.totalBottomInset + Spacing.md, for: .scrollContent)
      }
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .recurringEditTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextSecondary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: .commonSave)) {
            saveChanges()
          }
          .font(.tidexButton)
          .foregroundColor(.tidexBlue)
          .disabled(isSaving || !hasChanges || !canSave)
          .opacity(isSaving || !hasChanges || !canSave ? 0.5 : 1)
        }
      }
    }
    .onAppear {
      initializeEditState()
    }
    .interactiveDismissDisabled(hasChanges || editedStartTime == nil || editedEndTime == nil)
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

  /// A titled group, using the same header style as `DurationPicker`.
  private func section<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(title)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextMuted)
        .textCase(.uppercase)
        .accessibilityAddTraits(.isHeader)

      content()
    }
  }

  private var daysSection: some View {
    section(.recurringEditorDaysSection) {
      RepeatIntervalPicker(interval: $editedRepeatInterval)

      WeekdayChipBar(
        selectedDays: editedSelectedDays,
        onRemove: { weekday in
          // Don't allow removing the last weekday
          if editedSelectedDays.count > 1 {
            editedSelectedDays.removeValue(forKey: weekday)
          }
        }
      )

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

      EditRecurringCalendarView(
        displayMonth: displayMonth,
        selectedDays: $editedSelectedDays,
        repeatInterval: editedRepeatInterval,
        endCondition: editedEndCondition,
        existingShiftDates: []
      )
    }
  }

  private var exclusionsSection: some View {
    section(.recurringExclusionsTitle) {
      if editedExclusions.isEmpty {
        Text(.recurringExclusionsNone)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      } else {
        VStack(spacing: Spacing.xs) {
          ForEach(editedExclusions, id: \.self) { dateISO in
            exclusionRow(dateISO: dateISO)
          }
        }

        Text(.recurringExclusionsDescription)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
    }
  }

  private func exclusionRow(dateISO: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Text(formattedExclusionDate(dateISO))
        .font(.tidexLabel)
        .foregroundColor(.tidexTextPrimary)

      Spacer()

      Button {
        editedExclusions.removeAll { $0 == dateISO }
      } label: {
        Text(.recurringRestoreDateButton)
          .font(.tidexFootnoteStrong)
          .foregroundColor(.tidexBlue)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xxxs)
          .background(Color.tidexBlue.opacity(0.12))
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
  }

  private var deleteButton: some View {
    Button(role: .destructive) {
      showDeleteConfirmation = true
    } label: {
      Label(.recurringEditorDeleteButton, systemImage: "trash")
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexError)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Helpers

  private func initializeEditState() {
    // Parse start time
    editedStartTime = ShiftTimeFieldFormat.pickerDate(from: recurringShift.cleanStartTime)

    // Parse end time
    editedEndTime = ShiftTimeFieldFormat.pickerDate(from: recurringShift.cleanEndTime)

    // Set repeat interval
    editedRepeatInterval = recurringShift.repeat_interval_weeks

    // Set selected days
    editedSelectedDays = recurringShift.selected_days

    // Set end condition
    editedEndCondition = recurringShift.end_condition

    // Set exclusions
    editedExclusions = normalizeExclusions(recurringShift.effectiveExclusions)

    // Initialize display month to the earliest anchor date
    initializeDisplayMonth()
  }

  /// Initialize the display month to show the earliest anchor date
  private func initializeDisplayMonth() {
    let anchorDates = recurringShift.selected_days.values.sorted()
    guard let earliestAnchor = anchorDates.first,
      let anchorDate = Date.fromISODateString(earliestAnchor)
    else {
      // Default to current month if no anchors
      displayMonth = Date()
      return
    }

    // Set display month to the month containing the earliest anchor
    let calendar = Calendar.gregorianCurrent
    var components = calendar.dateComponents([.year, .month], from: anchorDate)
    components.day = 1
    displayMonth = calendar.date(from: components) ?? Date()
  }

  private func saveChanges() {
    guard hasChanges, canSave,
      let startTime = editedStartTime,
      let endTime = editedEndTime
    else { return }

    isSaving = true
    impactHaptic.impactOccurred()

    let result = RecurringShiftEditResult(
      recurringId: recurringShift.id,
      startTime: ShiftTimeFieldFormat.storedTime(
        from: startTime, original: recurringShift.cleanStartTime),
      endTime: ShiftTimeFieldFormat.storedTime(from: endTime, original: recurringShift.cleanEndTime),
      repeatIntervalWeeks: editedRepeatInterval,
      selectedDays: editedSelectedDays,
      endCondition: editedEndCondition,
      exclusions: normalizeExclusions(editedExclusions)
    )

    onSave?(result)
    dismiss()
  }

  private func deleteRecurringShift() {
    impactHaptic.impactOccurred()
    onDelete?()
    dismiss()
  }

  private func normalizeExclusions(_ exclusions: [String]) -> [String] {
    Array(Set(exclusions)).sorted()
  }

  private func formattedExclusionDate(_ dateISO: String) -> String {
    guard let date = Date.fromISODateString(dateISO) else { return dateISO }
    let formatter = DateFormatter()
    formatter.locale = Locale.appLocale
    formatter.setLocalizedDateFormatFromTemplate("EEEdMMMy")
    return formatter.string(from: date)
  }
}

// MARK: - Supporting Types

/// Converts between stored "HH:mm" shift times and the Date values used by time pickers.
enum ShiftTimeFieldFormat {
  /// Places a stored time on `day`. "24:00" becomes midnight, since pickers only read hour and minute.
  static func pickerDate(from time: String, on day: Date = Date()) -> Date? {
    let hourMinute = String(time.prefix(5))
    return Date.fromDateAndTime(
      day.toISODateString(),
      time: hourMinute == "24:00" ? "00:00" : hourMinute
    )
  }

  /// Formats a picker value, keeping a stored "24:00" end when the user left it at midnight.
  static func storedTime(from date: Date, original: String) -> String {
    let formatted = date.toHourMinuteString()
    return formatted == "00:00" && original.hasPrefix("24:00") ? "24:00" : formatted
  }
}

/// Result of editing a recurring shift
struct RecurringShiftEditResult {
  let recurringId: String
  let startTime: String  // HH:mm format
  let endTime: String  // HH:mm format
  let repeatIntervalWeeks: Int
  let selectedDays: SelectedDays
  let endCondition: EndCondition?
  let exclusions: [String]
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
      date_specific_pause_windows: nil,
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
