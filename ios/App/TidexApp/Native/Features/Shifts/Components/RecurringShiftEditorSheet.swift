import SwiftUI

/// Sheet for editing a recurring shift pattern
/// Allows editing start/end times, repeat interval, selected days, and end condition
struct RecurringShiftEditorSheet: View {
    let recurringShift: RecurringShiftRow
    let onSave: ((RecurringShiftEditResult) -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.localization) private var localization
    @Environment(\.dismiss) private var dismiss

    // MARK: - Edit State

    @State private var editedStartTime: Date = Date()
    @State private var editedEndTime: Date = Date()
    @State private var editedRepeatInterval: Int = 0
    @State private var editedSelectedDays: SelectedDays = [:]
    @State private var editedEndCondition: EndCondition? = nil

    // MARK: - UI State

    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Computed Properties

    /// Whether any changes have been made
    private var hasChanges: Bool {
        let newStartTime = formatTimeToString(editedStartTime)
        let newEndTime = formatTimeToString(editedEndTime)

        return newStartTime != recurringShift.cleanStartTime ||
               newEndTime != recurringShift.cleanEndTime ||
               editedRepeatInterval != recurringShift.repeat_interval_weeks ||
               editedSelectedDays != recurringShift.selected_days ||
               editedEndCondition != recurringShift.end_condition
    }

    /// Weekday labels (short form)
    private var weekdayLabels: [(key: String, label: String)] {
        let isNorwegian = localization.currentLocale == .norwegian
        if isNorwegian {
            return [
                ("1", "Man"),
                ("2", "Tir"),
                ("3", "Ons"),
                ("4", "Tor"),
                ("5", "Fre"),
                ("6", "Lør"),
                ("0", "Søn")
            ]
        } else {
            return [
                ("1", "Mon"),
                ("2", "Tue"),
                ("3", "Wed"),
                ("4", "Thu"),
                ("5", "Fri"),
                ("6", "Sat"),
                ("0", "Sun")
            ]
        }
    }

    /// Repeat interval options
    private var repeatIntervalOptions: [(value: Int, label: String)] {
        let isNorwegian = localization.currentLocale == .norwegian
        return (0...8).map { interval in
            let weeks = interval + 1
            if weeks == 1 {
                return (interval, isNorwegian ? "hver uke" : "every week")
            } else {
                return (interval, isNorwegian ? "hver \(weeks). uke" : "every \(weeks) weeks")
            }
        }
    }

    /// Duration type options
    private var durationOptions: [DurationOption] {
        let isNorwegian = localization.currentLocale == .norwegian
        return [
            DurationOption(type: .indefinite, label: isNorwegian ? "Uendelig" : "Indefinite"),
            DurationOption(type: .months, label: isNorwegian ? "Måneder" : "Months"),
            DurationOption(type: .years, label: isNorwegian ? "År" : "Years"),
            DurationOption(type: .endDate, label: isNorwegian ? "Sluttdato" : "End date")
        ]
    }

    /// Current duration type
    private var currentDurationType: DurationType {
        guard let condition = editedEndCondition else { return .indefinite }
        switch condition {
        case .months: return .months
        case .years: return .years
        case .endDate: return .endDate
        }
    }

    /// Current duration value (for months/years)
    private var currentDurationValue: Int {
        guard let condition = editedEndCondition else { return 1 }
        switch condition {
        case .months(let value): return value
        case .years(let value): return value
        case .endDate: return 1
        }
    }

    /// Current end date (for end date type)
    private var currentEndDate: Date {
        guard let condition = editedEndCondition,
              case .endDate(let dateStr) = condition,
              let date = Date.fromISODateString(dateStr) else {
            return Date()
        }
        return date
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Time Section
                    timeSection

                    // Weekday Selection
                    weekdaySection

                    // Repeat Interval
                    repeatIntervalSection

                    // Duration Section
                    durationSection

                    // Error message
                    if let error = errorMessage {
                        errorBanner(message: error)
                    }

                    // Action Buttons
                    actionButtons
                }
                .padding(20)
            }
            .background(Color.tidexBackground)
            .navigationTitle(localization.string("recurring.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localization.string("common.cancel")) {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.string("common.save")) {
                        saveChanges()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                    .disabled(isSaving || !hasChanges || editedSelectedDays.isEmpty)
                    .opacity(isSaving || !hasChanges || editedSelectedDays.isEmpty ? 0.5 : 1)
                }
            }
        }
        .onAppear {
            initializeEditState()
        }
        .interactiveDismissDisabled(hasChanges)
        .alert(
            localization.string("recurring.deleteConfirmTitle"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(localization.string("common.cancel"), role: .cancel) {}
            Button(localization.string("recurring.deleteConfirmButton"), role: .destructive) {
                deleteRecurringShift()
            }
        } message: {
            Text(localization.string("recurring.deleteConfirmMessage"))
        }
    }

    // MARK: - Sections

    private var timeSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.tidexBlue)
                Text(localization.string("shifts.timeSection"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            // Time pickers
            VStack(spacing: 16) {
                // Start time
                HStack {
                    Text(localization.string("shifts.startTime"))
                        .font(.system(size: 15))
                        .foregroundColor(.tidexTextSecondary)
                    Spacer()
                    DatePicker(
                        "",
                        selection: $editedStartTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(.tidexBlue)
                }

                Divider()

                // End time
                HStack {
                    Text(localization.string("shifts.endTime"))
                        .font(.system(size: 15))
                        .foregroundColor(.tidexTextSecondary)
                    Spacer()
                    DatePicker(
                        "",
                        selection: $editedEndTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(.tidexBlue)
                }

                // Cross-midnight info
                if isCrossMidnight {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.tidexBlue)
                        Text(localization.string("shifts.crossMidnightInfo"))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tidexSurfacePrimary)
            )
        }
    }

    private var weekdaySection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.tidexBlue)
                Text(localization.string("recurring.weekdaysSection"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            // Weekday chips
            HStack(spacing: 8) {
                ForEach(weekdayLabels, id: \.key) { weekday in
                    weekdayChip(key: weekday.key, label: weekday.label)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tidexSurfacePrimary)
            )
        }
    }

    @ViewBuilder
    private func weekdayChip(key: String, label: String) -> some View {
        let isSelected = editedSelectedDays[key] != nil

        Button {
            toggleWeekday(key)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
                )
        }
    }

    private var repeatIntervalSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "repeat")
                    .foregroundColor(.tidexBlue)
                Text(localization.string("recurring.repeatSection"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            // Repeat interval picker
            VStack(spacing: 0) {
                ForEach(repeatIntervalOptions, id: \.value) { option in
                    Button {
                        editedRepeatInterval = option.value
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.system(size: 15))
                                .foregroundColor(.tidexTextPrimary)
                            Spacer()
                            if editedRepeatInterval == option.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.tidexBlue)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }

                    if option.value < 8 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tidexSurfacePrimary)
            )
        }
    }

    private var durationSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "hourglass")
                    .foregroundColor(.tidexBlue)
                Text(localization.string("recurring.durationSection"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            VStack(spacing: 16) {
                // Duration type selector
                HStack(spacing: 8) {
                    ForEach(durationOptions, id: \.type) { option in
                        durationTypeButton(option)
                    }
                }

                // Value picker based on type
                switch currentDurationType {
                case .indefinite:
                    HStack(spacing: 8) {
                        Image(systemName: "infinity")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexBlue)
                        Text(localization.string("recurring.indefiniteHint"))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                        Spacer()
                    }
                case .months:
                    durationValuePicker(max: 120, unit: localization.currentLocale == .norwegian ? "måneder" : "months")
                case .years:
                    durationValuePicker(max: 10, unit: localization.currentLocale == .norwegian ? "år" : "years")
                case .endDate:
                    endDatePicker
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tidexSurfacePrimary)
            )
        }
    }

    @ViewBuilder
    private func durationTypeButton(_ option: DurationOption) -> some View {
        let isSelected = currentDurationType == option.type

        Button {
            setDurationType(option.type)
        } label: {
            Text(option.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
                )
        }
    }

    @ViewBuilder
    private func durationValuePicker(max: Int, unit: String) -> some View {
        HStack {
            Picker("", selection: Binding(
                get: { currentDurationValue },
                set: { setDurationValue($0) }
            )) {
                ForEach(1...max, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 80, height: 100)

            Text(unit)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)

            Spacer()
        }
    }

    private var endDatePicker: some View {
        HStack {
            Text(localization.string("recurring.endDateLabel"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: { currentEndDate },
                    set: { setEndDate($0) }
                ),
                in: Date()...,
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(.tidexBlue)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Save button
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
                    Text(localization.string("common.saveChanges"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(hasChanges && !editedSelectedDays.isEmpty ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
                .cornerRadius(12)
            }
            .disabled(isSaving || !hasChanges || editedSelectedDays.isEmpty)

            // Delete button
            if onDelete != nil {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        if isDeleting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .medium))
                        }
                        Text(localization.string("recurring.deleteButton"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.tidexError)
                    .cornerRadius(12)
                }
                .disabled(isDeleting)
            }
        }
        .padding(.top, 8)
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

    private var isCrossMidnight: Bool {
        let startStr = formatTimeToString(editedStartTime)
        let endStr = formatTimeToString(editedEndTime)
        return endStr <= startStr && endStr != "00:00"
    }

    private func initializeEditState() {
        // Parse start time
        if let startTime = parseTimeToDate(recurringShift.cleanStartTime) {
            editedStartTime = startTime
        }

        // Parse end time
        if let endTime = parseTimeToDate(recurringShift.cleanEndTime) {
            editedEndTime = endTime
        }

        // Set repeat interval
        editedRepeatInterval = recurringShift.repeat_interval_weeks

        // Set selected days
        editedSelectedDays = recurringShift.selected_days

        // Set end condition
        editedEndCondition = recurringShift.end_condition
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

    private func toggleWeekday(_ key: String) {
        if editedSelectedDays[key] != nil {
            // Don't allow removing the last weekday
            if editedSelectedDays.count > 1 {
                editedSelectedDays.removeValue(forKey: key)
            }
        } else {
            // Add new weekday with today's date as anchor (will be adjusted on save)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            editedSelectedDays[key] = formatter.string(from: Date())
        }
    }

    private func setDurationType(_ type: DurationType) {
        switch type {
        case .indefinite:
            editedEndCondition = nil
        case .months:
            editedEndCondition = .months(value: currentDurationValue)
        case .years:
            editedEndCondition = .years(value: currentDurationValue)
        case .endDate:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            editedEndCondition = .endDate(date: formatter.string(from: Date()))
        }
    }

    private func setDurationValue(_ value: Int) {
        switch currentDurationType {
        case .months:
            editedEndCondition = .months(value: value)
        case .years:
            editedEndCondition = .years(value: value)
        default:
            break
        }
    }

    private func setEndDate(_ date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        editedEndCondition = .endDate(date: formatter.string(from: date))
    }

    private func saveChanges() {
        guard hasChanges, !editedSelectedDays.isEmpty else { return }

        isSaving = true
        impactHaptic.impactOccurred()
        errorMessage = nil

        let result = RecurringShiftEditResult(
            recurringId: recurringShift.id,
            startTime: formatTimeToString(editedStartTime),
            endTime: formatTimeToString(editedEndTime),
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

/// Duration type options
enum DurationType: Equatable {
    case indefinite
    case months
    case years
    case endDate
}

/// Duration option for picker
struct DurationOption {
    let type: DurationType
    let label: String
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
