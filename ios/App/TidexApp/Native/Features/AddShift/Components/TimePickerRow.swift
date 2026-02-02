import SwiftUI
import UIKit

/// Custom time input field that accepts 4 digits and formats as HH:MM
/// Mimics the behavior of the web TimeInput component
struct NumericTimeInput: View {
    @Binding var time: Date?
    let label: String
    let focusField: FocusState<TimeField?>.Binding
    let field: TimeField
    let nextField: TimeField?
    let previousField: TimeField?
    let onComplete: (() -> Void)?

    @State private var inputValue: String = ""

    enum TimeField: Hashable {
        case start
        case end
    }

    private var isFocused: Bool {
        focusField.wrappedValue == field
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("00:00", text: $inputValue)
                .keyboardType(.numberPad)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
                .focused(focusField, equals: field)
                .onChange(of: inputValue) { _, newValue in
                    handleInputChange(newValue)
                }
                .onChange(of: time) { _, newTime in
                    // Sync input display with time value
                    if let newTime {
                        let formatted = formatDateToHHMM(newTime)
                        if inputValue != formatted {
                            inputValue = formatted
                        }
                    } else if !inputValue.isEmpty {
                        inputValue = ""
                    }
                }
                .onAppear {
                    // Initialize input from existing time value
                    if let time {
                        inputValue = formatDateToHHMM(time)
                    }
                }
                .onChange(of: isFocused) { wasFocused, nowFocused in
                    // When focus is lost, auto-complete partial hour input
                    if wasFocused && !nowFocused {
                        autoCompletePartialInput()
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.tidexBlue : Color.tidexBorder,
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    /// Auto-completes partial input when user taps away
    /// e.g., "9" → "09:00", "14" → "14:00", "930" → "09:30"
    private func autoCompletePartialInput() {
        let digits = inputValue.filter { $0.isNumber }

        // Only process if we have 1-3 digits (incomplete input)
        guard digits.count >= 1 && digits.count < 4 else { return }

        let completed: String
        switch digits.count {
        case 1:
            // Single digit: treat as hour, pad with zero and add :00
            // "9" → "09:00"
            completed = "0\(digits):00"
        case 2:
            // Two digits: treat as hour, add :00
            // "14" → "14:00", "09" → "09:00"
            completed = "\(digits):00"
        case 3:
            // Three digits: interpret based on first digits
            // "930" → "09:30" (single-digit hour + 2-digit minutes)
            // "143" → "14:30" (2-digit hour + partial minute, append 0)
            let potentialHour = Int(String(digits.prefix(2))) ?? 99
            if potentialHour <= 23 {
                // First 2 digits are a valid hour, last digit is partial minute
                // "143" → "14:30", "123" → "12:30"
                let hour = String(digits.prefix(2))
                let minute = String(digits.dropFirst(2)) + "0"
                completed = "\(hour):\(minute)"
            } else {
                // First 2 digits > 23, so first digit is hour, last 2 are minutes
                // "930" → "09:30", "253" → "02:53"
                // swiftlint:disable:next force_unwrapping
                let hour = "0\(digits.first!)"
                let minutes = String(digits.dropFirst())
                completed = "\(hour):\(minutes)"
            }
        default:
            return
        }

        // Validate and set the time
        if let date = parseTime(completed) {
            inputValue = completed
            time = date

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }

    private func handleInputChange(_ newValue: String) {
        // Remove all non-digit characters
        let digits = newValue.filter { $0.isNumber }

        // Detect backspace that empties the field - move to previous field
        // This enables continuous backspace navigation between fields
        if digits.isEmpty && previousField != nil {
            focusField.wrappedValue = previousField
            time = nil
            return
        }

        // Limit to 4 digits
        guard digits.count <= 4 else {
            inputValue = formatTimeInput(String(digits.prefix(4)))
            return
        }

        // Format the input
        let formatted = formatTimeInput(digits)
        inputValue = formatted

        // Only clear time when user explicitly empties the field
        // Don't clear during mid-edit (incomplete input is handled by autoCompletePartialInput on blur)
        if digits.isEmpty {
            time = nil
        }

        // Check if we have a complete valid time
        if digits.count == 4 {
            if let date = parseTime(formatted) {
                time = date

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                // Move to next field or dismiss keyboard
                if let next = nextField {
                    focusField.wrappedValue = next
                } else {
                    focusField.wrappedValue = nil
                    onComplete?()
                }
            }
        }
    }

    private func formatTimeInput(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }

        if digits.count <= 2 {
            return digits
        }

        // Format as HH:MM
        let hours = String(digits.prefix(2))
        let minutes = String(digits.dropFirst(2))
        return "\(hours):\(minutes)"
    }

    private func parseTime(_ formatted: String) -> Date? {
        let parts = formatted.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              hours >= 0, hours <= 23,
              minutes >= 0, minutes <= 59 else {
            return nil
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hours
        components.minute = minutes
        return calendar.date(from: components)
    }

    private func formatDateToHHMM(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Time Range Picker

/// Combined start/end time pickers with numeric keyboard input
/// Auto-advances from start to end field when 4 digits are entered
struct TimeRangePicker: View {
    @Binding var startTime: Date?
    @Binding var endTime: Date?
    var scrollProxy: ScrollViewProxy?
    var scrollId: String?
    /// Optional binding to expose/control which field is focused (for keyboard accessory)
    var focusedFieldBinding: Binding<NumericTimeInput.TimeField?>?
    @FocusState private var focusedField: NumericTimeInput.TimeField?
    
    /// Shortened label for start time field
    private var startLabel: String {
        "Start"
    }

    /// Shortened label for end time field
    private var endLabel: String {
        Locale.current.tidexIsNorwegian ? "Slutt" : "End"
    }

    var body: some View {
        HStack(spacing: 12) {
            NumericTimeInput(
                time: $startTime,
                label: startLabel,
                focusField: $focusedField,
                field: .start,
                nextField: .end,
                previousField: nil,
                onComplete: nil
            )

            NumericTimeInput(
                time: $endTime,
                label: endLabel,
                focusField: $focusedField,
                field: .end,
                nextField: nil,
                previousField: .start,
                onComplete: nil
            )
        }
        .id(scrollId)
        .onChange(of: focusedField) { _, newValue in
            // Sync internal focus state to external binding
            if focusedFieldBinding?.wrappedValue != newValue {
                focusedFieldBinding?.wrappedValue = newValue
            }
        }
        .onChange(of: focusedFieldBinding?.wrappedValue) { _, newValue in
            // Sync external binding to internal focus state (allows parent to control focus)
            if focusedField != newValue {
                focusedField = newValue
            }
        }
    }
}

// MARK: - Legacy Time Picker Row (for backward compatibility)

/// Reusable time picker with label
/// Uses native DatePicker with compact style
struct TimePickerRow: View {
    let label: String
    @Binding var time: Date
    var onTimeChange: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            DatePicker(
                "",
                selection: $time,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(.tidexBlue)
            .onChange(of: time) { _, _ in
                onTimeChange?()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VStack(spacing: 16) {
            TimeRangePicker(
                startTime: .constant(nil),
                endTime: .constant(nil)
            )
        }
        .padding()
        .background(Color.tidexBackground)
    }
}
