import SwiftUI
import UIKit

enum TimeInputField: Hashable {
  case start
  case end
}

final class TimeInputFocusController: ObservableObject {
  weak var startField: UITextField?
  weak var endField: UITextField?
  var onFocusChange: ((TimeInputField?) -> Void)?
  @Published private(set) var currentFocus: TimeInputField? {
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

    switch field {
    case .start:
      if let startField {
        startField.becomeFirstResponder()
        setCursorToEnd(startField)
      }
      endField?.resignFirstResponder()

    case .end:
      if let endField {
        endField.becomeFirstResponder()
        setCursorToEnd(endField)
      }
      startField?.resignFirstResponder()

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

private final class TimeInputTextField: UITextField {
  var onDeleteBackward: (() -> Bool)?

  override func deleteBackward() {
    if onDeleteBackward?() == true {
      return
    }
    super.deleteBackward()
  }
}

private func formatTimeInput(_ digits: String) -> String {
  guard !digits.isEmpty else { return "" }

  if digits.count <= 2 {
    return digits
  }

  let hours = String(digits.prefix(2))
  let minutes = String(digits.dropFirst(2))
  return "\(hours):\(minutes)"
}

private struct TimeTextField: UIViewRepresentable {
  struct Change {
    let formatted: String
    let digits: String
    let priorDigits: String
    let insertedDigits: String
    let didInsert: Bool
    let didDelete: Bool
    let caretAtEnd: Bool
    let caretAtStart: Bool
  }

  @Binding var text: String
  let field: TimeInputField
  let focusController: TimeInputFocusController
  let placeholder: String
  let label: String
  let onTextChange: (Change) -> Void
  @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 24

  func makeUIView(context: Context) -> UITextField {
    let textField = TimeInputTextField()
    textField.delegate = context.coordinator
    textField.keyboardType = .numberPad
    textField.autocorrectionType = .no
    textField.spellCheckingType = .no
    textField.autocapitalizationType = .none
    textField.textAlignment = .center
    textField.font = .monospacedSystemFont(ofSize: fontSize, weight: .medium)
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField.textColor = UIColor(Color.tidexTextPrimary)
    textField.tintColor = UIColor(Color.tidexBlue)
    textField.placeholder = placeholder
    textField.accessibilityLabel = label
    textField.text = text
    focusController.register(textField, field: field)
    context.coordinator.attach(textField)
    return textField
  }

  func updateUIView(_ uiView: UITextField, context: Context) {
    context.coordinator.parent = self
    uiView.font = .monospacedSystemFont(ofSize: fontSize, weight: .medium)
    uiView.accessibilityLabel = label
    if uiView.text != text {
      uiView.text = text
      if uiView.isFirstResponder {
        context.coordinator.setCursor(uiView, position: text.count)
      }
    }

    let shouldFocus = focusController.currentFocus == field
    if shouldFocus != uiView.isFirstResponder {
      // Changing the first responder during a SwiftUI update can reenter its view graph.
      // Recheck the requested field after the update so rapid focus changes stay ordered.
      DispatchQueue.main.async { [weak uiView, weak focusController] in
        guard let uiView, let focusController else { return }
        if focusController.currentFocus == field {
          if uiView.window != nil, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
            context.coordinator.setCursor(uiView, position: uiView.text?.count ?? 0)
          }
        } else if uiView.isFirstResponder {
          uiView.resignFirstResponder()
        }
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: TimeTextField
    private weak var textField: TimeInputTextField?

    init(parent: TimeTextField) {
      self.parent = parent
    }

    func attach(_ textField: TimeInputTextField) {
      self.textField = textField
      textField.onDeleteBackward = { [weak self] in
        self?.handleDeleteBackward() ?? false
      }
    }

    func textFieldDidBeginEditing(_: UITextField) {
      parent.focusController.focus(parent.field)
    }

    func textFieldDidEndEditing(_: UITextField) {
      if parent.focusController.currentFocus == parent.field {
        parent.focusController.focus(nil)
      }
    }

    func textField(
      _ textField: UITextField, shouldChangeCharactersIn range: NSRange,
      replacementString string: String
    ) -> Bool {
      let currentText = textField.text ?? ""
      // swiftlint:disable:next explicit_type_interface
      let currentDigits = currentText.filter(\.isNumber)

      let adjustedRange = adjustRangeForColonBackspace(range, in: currentText, replacement: string)
      let proposedText = (currentText as NSString).replacingCharacters(
        in: adjustedRange, with: string)

      // swiftlint:disable:next explicit_type_interface
      let proposedDigits = proposedText.filter(\.isNumber)
      let limitedDigits = String(proposedDigits.prefix(4))
      let formatted = formatTimeInput(limitedDigits)

      let replacementLength = (string as NSString).length
      let cursorPosition = adjustedRange.location + replacementLength
      let digitsBeforeCursor = countDigits(in: proposedText, upToUTF16: cursorPosition)
      let cappedDigitsBeforeCursor = min(digitsBeforeCursor, limitedDigits.count)
      let caretPosition = caretIndex(
        forDigitsBefore: cappedDigitsBeforeCursor, digitsCount: limitedDigits.count)

      textField.text = formatted
      parent.text = formatted
      setCursor(textField, position: caretPosition)

      let didInsert = string.rangeOfCharacter(from: .decimalDigits) != nil
      // swiftlint:disable:next explicit_type_interface
      let insertedDigits = string.filter(\.isNumber)
      let didDelete = string.isEmpty && adjustedRange.length > 0
      let caretAtEnd = caretPosition == formatted.count
      let caretAtStart = caretPosition == 0

      parent.onTextChange(
        Change(
          formatted: formatted,
          digits: limitedDigits,
          priorDigits: currentDigits,
          insertedDigits: insertedDigits,
          didInsert: didInsert,
          didDelete: didDelete,
          caretAtEnd: caretAtEnd,
          caretAtStart: caretAtStart
        )
      )

      return false
    }

    private func handleDeleteBackward() -> Bool {
      guard let textField else { return false }
      let currentText = textField.text ?? ""
      // swiftlint:disable:next explicit_type_interface
      let currentDigits = currentText.filter(\.isNumber)
      let caretOffset = currentCaretOffset(in: textField)

      guard currentDigits.count <= 2, caretOffset == 0 else { return false }

      textField.text = ""
      parent.text = ""
      setCursor(textField, position: 0)

      parent.onTextChange(
        Change(
          formatted: "",
          digits: "",
          priorDigits: currentDigits,
          insertedDigits: "",
          didInsert: false,
          didDelete: true,
          caretAtEnd: true,
          caretAtStart: true
        )
      )

      return true
    }

    private func adjustRangeForColonBackspace(
      _ range: NSRange, in text: String, replacement: String
    ) -> NSRange {
      guard replacement.isEmpty, range.length == 1 else { return range }
      let nsText = text as NSString
      guard range.location < nsText.length else { return range }
      let char = nsText.substring(with: range)
      guard char == ":", range.location > 0 else { return range }
      return NSRange(location: range.location - 1, length: 1)
    }

    private func countDigits(in text: String, upToUTF16 position: Int) -> Int {
      let nsText = text as NSString
      let safePosition = min(position, nsText.length)
      let prefix = nsText.substring(to: safePosition)
      return prefix.filter(\.isNumber).count
    }

    private func caretIndex(forDigitsBefore digitsBefore: Int, digitsCount: Int) -> Int {
      guard digitsCount >= 3 else { return digitsBefore }
      if digitsBefore <= 2 {
        return digitsBefore
      }
      return digitsBefore + 1
    }

    private func currentCaretOffset(in textField: UITextField) -> Int {
      guard let selectedRange = textField.selectedTextRange else { return 0 }
      return textField.offset(from: textField.beginningOfDocument, to: selectedRange.start)
    }

    fileprivate func setCursor(_ textField: UITextField, position: Int) {
      guard let start = textField.position(from: textField.beginningOfDocument, offset: position)
      else {
        return
      }
      textField.selectedTextRange = textField.textRange(from: start, to: start)
    }
  }
}

/// Custom time input field that accepts 4 digits and formats as HH:MM
/// Mimics the behavior of the web TimeInput component
struct NumericTimeInput: View {
  @Binding var time: Date?
  let label: String
  @ObservedObject var focusController: TimeInputFocusController
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

    let calendar = Calendar.current
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
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
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
  /// Optional accessory displayed to the left of recent time chips.
  var leadingChipAccessory: AnyView?  // swiftlint:disable:this explicit_acl
  @StateObject private var focusController = TimeInputFocusController()
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

      if showsRecentTimeChips {
        HStack(spacing: Spacing.xs) {
          if let leadingChipAccessory {
            leadingChipAccessory
              .fixedSize(horizontal: true, vertical: false)
          }

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
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
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

    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = hours == 24 ? 0 : hours
    components.minute = minutes
    return calendar.date(from: components)
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
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(label)
        .font(.tidexCaptionStrong)
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
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
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
