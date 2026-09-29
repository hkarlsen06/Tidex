import Observation
import SwiftUI
import UIKit

enum TimeInputField: Hashable {
  case start
  case end
}

@Observable
final class TimeInputFocusController {
  @ObservationIgnored weak var startField: UITextField?
  @ObservationIgnored weak var endField: UITextField?
  @ObservationIgnored var onFocusChange: ((TimeInputField?) -> Void)?
  private(set) var currentFocus: TimeInputField? {
    didSet {
      if oldValue != currentFocus {
        onFocusChange?(currentFocus)
      }
    }
  }

  func register(_ textField: UITextField, field: TimeInputField) {
    switch field {
    case .start:
      startField = textField

    case .end:
      endField = textField
    }
  }

  func focus(_ field: TimeInputField?) {
    if currentFocus != field {
      currentFocus = field
    }

    // Let the destination take over before releasing the current responder. During
    // SwiftUI layout it may not be attached yet; updateUIView will retry the handoff.
    switch field {
    case .start:
      if let startField {
        startField.becomeFirstResponder()
        setCursorToEnd(startField)
      }

    case .end:
      if let endField {
        endField.becomeFirstResponder()
        setCursorToEnd(endField)
      }

    case .none:
      startField?.resignFirstResponder()
      endField?.resignFirstResponder()
    }
  }

  @discardableResult
  func focusAndInsert(_ text: String, into field: TimeInputField) -> Bool {
    guard !text.isEmpty, let textField = textField(for: field) else { return false }
    focus(field)
    textField.insertText(text)
    return true
  }

  private func textField(for field: TimeInputField) -> UITextField? {
    switch field {
    case .start:
      return startField

    case .end:
      return endField
    }
  }

  private func setCursorToEnd(_ textField: UITextField) {
    let length = textField.text?.count ?? 0
    guard let start = textField.position(from: textField.beginningOfDocument, offset: length) else {
      return
    }
    textField.selectedTextRange = textField.textRange(from: start, to: start)
  }
}

/// Custom time input field that accepts 4 digits and formats as HH:MM
/// Mimics the behavior of the web TimeInput component
struct NumericTimeInput: View {
  @Binding var time: Date?
  let label: String
  var focusController: TimeInputFocusController
  let field: TimeInputField
  let nextField: TimeInputField?
  let previousField: TimeInputField?
  let onComplete: (() -> Void)?

  @State private var inputValue: String = ""
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var textFieldHeight: CGFloat = 30

  private var isFocused: Bool {
    focusController.currentFocus == field
  }

  private var hasInvalidInput: Bool {
    let digitCount = inputValue.filter(\.isNumber).count
    return !inputValue.isEmpty && (digitCount == 4 || !isFocused) && parseTime(inputValue) == nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      inputLayout {
        inputLabel
        textField
      }

      if hasInvalidInput {
        Text(.addShiftTimeInputInvalid)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexError)
          .fixedSize(horizontal: false, vertical: true)
          .announcesToVoiceOver(String(localized: .addShiftTimeInputInvalid))
      }
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .frame(maxWidth: .infinity)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .overlay {
      if isFocused || hasInvalidInput {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .strokeBorder(hasInvalidInput ? Color.tidexError : Color.tidexBlue, lineWidth: 1)
      }
    }
    .animation(.easeInOut(duration: 0.15), value: isFocused)
  }

  private var inputLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
  }

  private var inputLabel: some View {
    Text(label)
      .font(.tidexCaptionStrong)
      .foregroundColor(.tidexTextMuted)
      .textCase(.uppercase)
      .tracking(0.5)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityHidden(true)
  }

  private var textField: some View {
    TimeTextField(
      text: $inputValue,
      field: field,
      focusController: focusController,
      placeholder: "00:00",
      label: label,
      onTextChange: { change in
        handleTextChange(change)
      }
    )
    .frame(maxWidth: .infinity)
    .frame(height: textFieldHeight)
    .onChange(of: time) { _, newTime in
      // Sync input display with time value
      if let newTime {
        let formatted = displayString(for: newTime)
        if inputValue != formatted {
          inputValue = formatted
        }
      } else if !isFocused, !inputValue.isEmpty {
        inputValue = ""
      }
    }
    .onAppear {
      // Initialize input from existing time value
      if let time {
        inputValue = displayString(for: time)
      }
    }
    .onChange(of: isFocused) { wasFocused, nowFocused in
      // When focus is lost, auto-complete partial hour input
      if wasFocused, !nowFocused {
        autoCompletePartialInput()
      }
    }
  }

  /// Auto-completes partial input when user taps away
  /// e.g., "9" → "09:00", "14" → "14:00", "930" → "09:30"
  private func autoCompletePartialInput() {
    // swiftlint:disable:next explicit_type_interface
    let digits = inputValue.filter(\.isNumber)

    // Only process if we have 1-3 digits (incomplete input)
    // swiftlint:disable:next conditional_returns_on_newline no_magic_numbers
    guard digits.count >= 1, digits.count < 4 else { return }

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

  private func handleTextChange(_ change: TimeTextField.Change) {
    if let next = nextField,
      change.didInsert,
      !change.insertedDigits.isEmpty,
      change.priorDigits.count == 4,
      parseTime(formatTimeInput(change.priorDigits)) != nil,
      change.digits == change.priorDigits,
      change.caretAtEnd,
      focusController.focusAndInsert(change.insertedDigits, into: next)
    {
      return
    }

    if change.digits.isEmpty {
      time = nil
      if change.didDelete, previousField != nil {
        focusController.focus(previousField)
      }
      return
    }

    // The bound value must describe the text currently visible, including incomplete edits.
    // Keep the text in place so the user can correct it without saving an older valid time.
    time = change.digits.count == 4 ? parseTime(change.formatted) : nil
    if time != nil {

      let generator = UIImpactFeedbackGenerator(style: .light)
      generator.impactOccurred()

      if change.caretAtEnd {
        if let next = nextField {
          focusController.focus(next)
        } else {
          focusController.focus(nil as TimeInputField?)
          onComplete?()
        }
      }
    }
  }

  private func parseTime(_ formatted: String) -> Date? {
    let parts = formatted.split(separator: ":")
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      hours >= 0, hours <= 24,
      minutes >= 0, minutes <= 59
    else {
      return nil
    }

    // 24:00 is only valid as exactly end-of-day (24:01+ is invalid)
    // swiftlint:disable:next conditional_returns_on_newline no_magic_numbers
    if hours == 24, minutes != 0 { return nil }

    let calendar = Calendar.gregorianCurrent
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    // Treat 24:00 as midnight (00:00) — the payroll engine's
    // cross-midnight logic handles this correctly
    components.hour = hours == 24 ? 0 : hours
    components.minute = minutes
    return calendar.date(from: components)
  }

  /// Format Date for display, showing "24:00" for midnight in the end field
  private func displayString(for date: Date) -> String {
    let formatted = formatDateToHHMM(date)
    if field == .end, formatted == "00:00" {
      return "24:00"
    }
    return formatted
  }

  private func formatDateToHHMM(_ date: Date) -> String {
    date.toHourMinuteString()
  }
}

// MARK: - Time Range Picker

/// Combined start/end time pickers with numeric keyboard input
/// Auto-advances from start to end field when 4 digits are entered
/// Includes recent time chips below the inputs for quick selection
struct TimeRangePicker: View {
  @Binding var startTime: Date?
  @Binding var endTime: Date?
  var scrollProxy: ScrollViewProxy?
  var scrollId: String?
  /// Optional binding to expose/control which field is focused (for keyboard accessory)
  var focusedFieldBinding: Binding<TimeInputField?>?
  /// Optional preset chip ranges (used by onboarding simulator).
  var presetRanges: [TimeRangeCount]?  // swiftlint:disable:this discouraged_optional_collection explicit_acl
  /// Whether to show recent/preset time chips below the inputs.
  var showsRecentTimeChips = true
  /// Shows the recent time chips above the inputs instead of below them.
  var chipsAboveInputs = false
  @State private var focusController = TimeInputFocusController()
  @ScaledMetric(relativeTo: .body) private var compactInputWidth: CGFloat = 156
  @ScaledMetric(relativeTo: .body) private var compactInputHeight: CGFloat = 58

  /// Shortened label for start time field
  private var startLabel: String {
    String(localized: .commonStart)
  }

  /// Shortened label for end time field
  private var endLabel: String {
    String(localized: .commonEnd)
  }

  var body: some View {
    VStack(spacing: Spacing.xs) {
      if chipsAboveInputs {
        recentTimeChipRow
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: Spacing.sm) {
          startInput.frame(width: compactInputWidth)
          endInput.frame(width: compactInputWidth)
        }
        VStack(spacing: Spacing.sm) {
          startInput
          endInput
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)

      if !chipsAboveInputs {
        recentTimeChipRow
      }
    }
    .id(scrollId)
    .onAppear {
      focusController.onFocusChange = { (focused: TimeInputField?) in
        if focusedFieldBinding?.wrappedValue != focused {
          focusedFieldBinding?.wrappedValue = focused
        }
      }
      focusController.focus(focusedFieldBinding?.wrappedValue as TimeInputField?)
    }
    .onChange(of: focusedFieldBinding?.wrappedValue) { _, newValue in
      if focusController.currentFocus != newValue {
        focusController.focus(newValue)
      }
    }
  }

  @ViewBuilder
  private var recentTimeChipRow: some View {
    if showsRecentTimeChips {
      RecentTimesChips(
        onSelect: { range in
          applyTimeRange(range)
        },
        activeRangeId: activeRangeId,
        presetRanges: presetRanges
      )
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var startInput: some View {
    NumericTimeInput(
      time: $startTime, label: startLabel, focusController: focusController,
      field: .start, nextField: .end, previousField: nil, onComplete: nil
    )
    .frame(minHeight: compactInputHeight)
  }

  private var endInput: some View {
    NumericTimeInput(
      time: $endTime, label: endLabel, focusController: focusController,
      field: .end, nextField: nil, previousField: .start, onComplete: nil
    )
    .frame(minHeight: compactInputHeight)
  }

  /// ID of the currently active time range chip, if start/end match a chip's times
  private var activeRangeId: String? {
    guard let start = startTime, let end = endTime else { return nil }
    let startHHmm = formatDateToHHmm(start)
    let endHHmm = formatDateToHHmm(end)
    return "\(startHHmm)-\(endHHmm)"
  }

  /// Apply a recent time range to the inputs, or clear if already active (toggle)
  private func applyTimeRange(_ timeRange: TimeRangeCount) {
    // Dismiss keyboard by clearing focus
    focusController.focus(nil as TimeInputField?)

    // Toggle: if this chip is already active, clear the times
    if timeRange.id == activeRangeId {
      startTime = nil
      endTime = nil

      let generator = UIImpactFeedbackGenerator(style: .light)
      generator.impactOccurred()
      return
    }

    // Parse start time
    if let start = parseTimeFromHHmm(timeRange.startTime) {
      startTime = start
    }
    // Parse end time
    if let end = parseTimeFromHHmm(timeRange.endTime) {
      endTime = end
    }

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Format a Date to HH:mm string for comparison
  private func formatDateToHHmm(_ date: Date) -> String {
    date.toHourMinuteString()
  }

  /// Parse HH:mm string to Date
  private func parseTimeFromHHmm(_ timeString: String) -> Date? {
    let parts = timeString.split(separator: ":")
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      hours >= 0, hours <= 24,
      minutes >= 0, minutes <= 59
    else {
      return nil
    }

    // swiftlint:disable:next conditional_returns_on_newline no_magic_numbers
    if hours == 24, minutes != 0 { return nil }

    let calendar = Calendar.gregorianCurrent
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = hours == 24 ? 0 : hours
    components.minute = minutes
    return calendar.date(from: components)
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    VStack(spacing: Spacing.md) {
      TimeRangePicker(
        startTime: .constant(nil),
        endTime: .constant(nil)
      )
    }
    .padding()
    .background(Color.tidexBackground)
  }
}
