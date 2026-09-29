import SwiftUI
import UIKit

final class TimeInputTextField: UITextField {
  var onDeleteBackward: (() -> Bool)?

  override func deleteBackward() {
    if onDeleteBackward?() == true {
      return
    }
    super.deleteBackward()
  }
}

func formatTimeInput(_ digits: String) -> String {
  guard !digits.isEmpty else { return "" }

  if digits.count <= 2 {
    return digits
  }

  let hours = String(digits.prefix(2))
  let minutes = String(digits.dropFirst(2))
  return "\(hours):\(minutes)"
}

struct TimeTextField: UIViewRepresentable {
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
        } else if focusController.currentFocus == nil, uiView.isFirstResponder {
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
