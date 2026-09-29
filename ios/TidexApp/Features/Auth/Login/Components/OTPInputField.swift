import SwiftUI
import UIKit

// MARK: - Digit Box

/// Individual digit display box - extracted for performance
internal struct DigitBox: View {
  private let cursorWidth: CGFloat = 2
  private let cursorHeight: CGFloat = 24
  private let activeBorderWidth: CGFloat = 2
  private let inactiveBorderWidth: CGFloat = 1
  @ScaledMetric(relativeTo: .title2) private var scaledBoxWidth: CGFloat = 48
  @ScaledMetric(relativeTo: .title2) private var scaledBoxHeight: CGFloat = 56

  // Capped so three boxes still fit in a row at the largest text sizes.
  private var boxWidth: CGFloat {
    min(scaledBoxWidth, 96)  // swiftlint:disable:this no_magic_numbers
  }

  private var boxHeight: CGFloat {
    min(scaledBoxHeight, 112)  // swiftlint:disable:this no_magic_numbers
  }

  private let digit: String?
  private let isCurrentPosition: Bool
  private let hasError: Bool
  private let isFilled: Bool
  private let cursorVisible: Bool

  internal var body: some View {
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

  internal init(
    digit: String?,
    isCurrentPosition: Bool,
    hasError: Bool,
    isFilled: Bool,
    cursorVisible: Bool
  ) {
    self.digit = digit
    self.isCurrentPosition = isCurrentPosition
    self.hasError = hasError
    self.isFilled = isFilled
    self.cursorVisible = cursorVisible
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

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @FocusState private var isFocused: Bool
  @State private var cursorVisible: Bool = true
  @State private var cursorTimer: Timer?

  private let digitCount: Int = 6
  private let cursorBlinkInterval: TimeInterval = 0.5

  internal var body: some View {
    VStack(spacing: Spacing.xs) {
      // The text field covers the boxes, so tapping anywhere on them opens the keyboard.
      digitBoxes
        .overlay { hiddenTextField }

      // Error message
      if let error, !error.isEmpty {
        Text(error)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexError)
          .multilineTextAlignment(.center)
          .announcesToVoiceOver(error)
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
    .sensoryFeedback(.impact(weight: .light), trigger: code) { _, newValue in
      !newValue.isEmpty
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: code) { _, newValue in
      newValue.count == digitCount
    }
  }

  /// The six boxes sit in one row and split into two rows of three when large text makes them too wide.
  @ViewBuilder
  private var digitBoxes: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: Spacing.xs) {
          digitRow(indices: 0..<3)  // swiftlint:disable:this no_magic_numbers
          digitRow(indices: 3..<6)  // swiftlint:disable:this no_magic_numbers
        }
      } else {
        digitRow(indices: 0..<digitCount)
      }
    }
    // The boxes only draw the code. The text field below is the one element VoiceOver reads.
    .accessibilityHidden(true)
  }

  private func digitRow(indices: Range<Int>) -> some View {
    HStack(spacing: Spacing.xs) {
      ForEach(indices, id: \.self) { index in
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
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // Call completion when all digits entered
    if code.count == digitCount {
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
