import SwiftUI

/// 6-digit OTP input field with individual digit boxes
struct OTPInputField: View {
    @Binding var code: String
    var error: String? = nil
    var onComplete: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    private let digitCount = 6

    var body: some View {
        VStack(spacing: 8) {
            // Hidden text field for actual input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: code) { _, newValue in
                    // Limit to 6 digits
                    if newValue.count > digitCount {
                        code = String(newValue.prefix(digitCount))
                    }
                    // Filter non-digits
                    code = code.filter { $0.isNumber }
                    // Call completion when all digits entered
                    if code.count == digitCount {
                        onComplete?()
                    }
                }

            // Visual digit boxes
            HStack(spacing: 8) {
                ForEach(0..<digitCount, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }

            // Error message
            if let error = error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.tidexError)
            }
        }
        .onAppear {
            // Auto-focus on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
    }

    @ViewBuilder
    private func digitBox(at index: Int) -> some View {
        let digit = getDigit(at: index)
        let isCurrentPosition = index == code.count && isFocused

        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tidexSurfaceSecondary)
                .frame(width: 48, height: 56)

            // Border
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor(at: index, isCurrentPosition: isCurrentPosition), lineWidth: 1)
                .frame(width: 48, height: 56)

            // Digit or cursor
            if let digit = digit {
                Text(digit)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(.tidexTextPrimary)
            } else if isCurrentPosition {
                // Blinking cursor
                Rectangle()
                    .fill(Color.tidexBrandPrimary)
                    .frame(width: 2, height: 24)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: isCurrentPosition)
            }
        }
    }

    private func getDigit(at index: Int) -> String? {
        guard index < code.count else { return nil }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }

    private func borderColor(at index: Int, isCurrentPosition: Bool) -> Color {
        if error != nil {
            return .tidexError
        }
        if isCurrentPosition {
            return .tidexBrandPrimary
        }
        if index < code.count {
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
    .background(Color.tidexDarkBackground)
}
