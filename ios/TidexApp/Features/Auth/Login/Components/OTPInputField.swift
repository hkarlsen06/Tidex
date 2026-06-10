import SwiftUI
import UIKit

// MARK: - Digit Box

/// Individual digit display box - extracted for performance
private struct DigitBox: View {
  private let cursorWidth: CGFloat = 2
  private let cursorHeight: CGFloat = 24
  private let activeBorderWidth: CGFloat = 2
  private let inactiveBorderWidth: CGFloat = 1
  private let boxWidth: CGFloat = 48
  private let boxHeight: CGFloat = 56

  private let digit: String?
  private let isCurrentPosition: Bool
  private let hasError: Bool
  private let isFilled: Bool
  private let cursorVisible: Bool

  private var body: some View {
    ZStack {
      // Background
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(Color.tidexSurfaceSecondary)

      // Border
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .stroke(borderColor, lineWidth: isCurrentPosition ? activeBorderWidth : inactiveBorderWidth)

      // Digit or cursor
      if let digit {
        Text(digit)
          .font(.tidexMonoTitle)
          .foregroundColor(.tidexTextPrimary)
      } else if isCurrentPosition, cursorVisible {
        // Blinking cursor
        RoundedRectangle(cornerRadius: inactiveBorderWidth)
          .fill(Color.tidexBrandPrimary)
          .frame(width: cursorWidth, height: cursorHeight)
      }
    }
    .frame(width: boxWidth, height: boxHeight)
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

/// 6-digit OTP input field with individual digit boxes
/// Optimized for instant keyboard response
internal struct OTPInputField: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

  @Binding internal var code: String
  internal var error: String?
  internal var onComplete: (() -> Void)?
  internal var autoFocus: Bool = true

  @FocusState private var isFocused: Bool
  @State private var cursorVisible: Bool = true
  @State private var cursorTimer: Timer?

  private let digitCount: Int = 6
  private let cursorBlinkInterval: TimeInterval = 0.5
  private let textFieldHeight: CGFloat = 56

  internal var body: some View {
    VStack(spacing: Spacing.xs) {
      ZStack {
        digitBoxes
        hiddenTextField
      }
      .onTapGesture {
        isFocused = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }
      .accessibilityAddTraits(.isButton)

      // Error message
      if let error, !error.isEmpty {
        Text(error)
          .font(.tidexCaptionRegular)
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
    .onDisappear {
      cursorTimer?.invalidate()
      cursorTimer = nil
    }
  }

  private var digitBoxes: some View {
    HStack(spacing: Spacing.xs) {
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
  }

  private var hiddenTextField: some View {
    TextField("", text: $code)
      .keyboardType(.numberPad)
      .textContentType(.oneTimeCode)
      .focused($isFocused)
      .foregroundColor(.clear)
      .tint(.clear)
      .accentColor(.clear)
      .frame(maxWidth: .infinity)
      .frame(height: textFieldHeight)
      .accessibilityLabel(Text(.securityPasswordOtpLabel))
      .onChange(of: code) { _, newValue in
        handleCodeChange(newValue)
      }
  }

  private func handleCodeChange(_ newValue: String) {
    // Filter non-digits and limit to 6 characters
    let filtered: String = newValue.filter(\.isNumber)
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
    guard index < code.count else {
      return nil
    }
    let stringIndex: String.Index = code.index(code.startIndex, offsetBy: index)
    return String(code[stringIndex])
  }

  private func startCursorBlink() {
    cursorTimer?.invalidate()
    cursorTimer = nil

    guard !reduceMotion else {
      cursorVisible = true
      return
    }

    cursorTimer = Timer.scheduledTimer(withTimeInterval: cursorBlinkInterval, repeats: true) { _ in
      cursorVisible.toggle()
    }
  }
}

#Preview {
  VStack(spacing: Spacing.lg) {
    OTPInputField(code: .constant(""))

    OTPInputField(code: .constant("123"))

    OTPInputField(code: .constant("123456"))

    OTPInputField(code: .constant("123"), error: "Invalid code")
  }
  .padding()
  .background(Color.tidexBackground)
}
