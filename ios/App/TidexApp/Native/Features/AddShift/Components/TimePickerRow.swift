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
        VStack(alignment: .leading, spacing: 8) {
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
                    // Sync input when time is externally cleared
                    if newTime == nil && !inputValue.isEmpty {
                        inputValue = ""
                    }
                }
        }
        .padding(16)
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

    private func handleInputChange(_ newValue: String) {
        // Remove all non-digit characters
        let digits = newValue.filter { $0.isNumber }

        // Limit to 4 digits
        guard digits.count <= 4 else {
            inputValue = formatTimeInput(String(digits.prefix(4)))
            return
        }

        // Format the input
        let formatted = formatTimeInput(digits)
        inputValue = formatted

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
    @FocusState private var focusedField: NumericTimeInput.TimeField?
    @Environment(\.localization) private var localization

    var body: some View {
        HStack(spacing: 12) {
            NumericTimeInput(
                time: $startTime,
                label: localization.string("addShift.startTime"),
                focusField: $focusedField,
                field: .start,
                nextField: .end,
                onComplete: nil
            )

            NumericTimeInput(
                time: $endTime,
                label: localization.string("addShift.endTime"),
                focusField: $focusedField,
                field: .end,
                nextField: nil,
                onComplete: nil
            )
        }
        .id(scrollId)
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
    .environment(\.localization, LocalizationManager.shared)
}
