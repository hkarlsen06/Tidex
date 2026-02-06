import SwiftUI
import UIKit

/// 6-digit OTP input field with individual digit boxes
/// Optimized for instant keyboard response
struct OTPInputField: View {
  @Binding var code: String
  var error: String? = nil
  var onComplete: (() -> Void)? = nil
  var autoFocus: Bool = true

  @FocusState private var isFocused: Bool
  @State private var cursorVisible = true

  private let digitCount = 6

  var body: some View {
    VStack(spacing: 8) {
      // Visual digit boxes with hidden TextField overlay
      ZStack {
        // Visual digit boxes (behind the text field)
        HStack(spacing: 8) {
          ForEach(0..<digitCount, id: \.self) { index in
            DigitBox(
              digit: getDigit(at: index),
              isCurrentPosition: index == code.count && isFocused,
              hasError: error != nil,
              isFilled: index < code.count,
              cursorVisible: cursorVisible
            )
          }
        }

        // Text field on top - transparent but receives all touches including autofill
        TextField("", text: $code)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
          .focused($isFocused)
          .foregroundColor(.clear)
          .tint(.clear)
          .accentColor(.clear)
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .onChange(of: code) { _, newValue in
            handleCodeChange(newValue)
          }
      }
      .onTapGesture {
        isFocused = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }

      // Error message
      if let error = error, !error.isEmpty {
        Text(error)
          .font(.system(size: 12))
          .foregroundColor(.tidexError)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .onAppear {
      if autoFocus {
        // Focus immediately - no delay needed
        isFocused = true
      }
      // Start cursor blinking
      startCursorBlink()
    }
  }

  private func handleCodeChange(_ newValue: String) {
    // Filter non-digits and limit to 6 characters
    let filtered = newValue.filter { $0.isNumber }
    if filtered.count > digitCount {
      code = String(filtered.prefix(digitCount))
    } else if filtered != newValue {
      code = filtered
    }

    // Haptic feedback on digit entry
    if !code.isEmpty {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // Call completion when all digits entered
    if code.count == digitCount {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      onComplete?()
    }
  }

  private func getDigit(at index: Int) -> String? {
    guard index < code.count else { return nil }
    let stringIndex = code.index(code.startIndex, offsetBy: index)
    return String(code[stringIndex])
  }

  private func startCursorBlink() {
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
      cursorVisible.toggle()
    }
  }
}

// MARK: - Digit Box

/// Individual digit display box - extracted for performance
private struct DigitBox: View {
  let digit: String?
  let isCurrentPosition: Bool
  let hasError: Bool
  let isFilled: Bool
  let cursorVisible: Bool

  var body: some View {
    ZStack {
      // Background
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.tidexSurfaceSecondary)

      // Border
      RoundedRectangle(cornerRadius: 8)
        .stroke(borderColor, lineWidth: isCurrentPosition ? 2 : 1)

      // Digit or cursor
      if let digit = digit {
        Text(digit)
          .font(.system(size: 24, weight: .semibold, design: .monospaced))
          .foregroundColor(.tidexTextPrimary)
      } else if isCurrentPosition && cursorVisible {
        // Blinking cursor
        RoundedRectangle(cornerRadius: 1)
          .fill(Color.tidexBrandPrimary)
          .frame(width: 2, height: 24)
      }
    }
    .frame(width: 48, height: 56)
  }

  private var borderColor: Color {
    if hasError {
      return .tidexError
    }
    if isCurrentPosition {
      return .tidexBrandPrimary
    }
    if isFilled {
      return .tidexBorder
    }
    return .tidexBorderSubtle
  }
}

#Preview {
  VStack(spacing: 24) {
    OTPInputField(code: .constant(""))

    OTPInputField(code: .constant("123"))

    OTPInputField(code: .constant("123456"))

    OTPInputField(code: .constant("123"), error: "Invalid code")
  }
  .padding()
  .background(Color.tidexBackground)
}
