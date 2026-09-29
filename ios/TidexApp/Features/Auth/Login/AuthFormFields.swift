import SwiftUI

// MARK: - Native Text Field

/// A text field styled like native iOS grouped forms
struct NativeTextField: View {
  let placeholder: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default
  // swiftlint:disable:next explicit_acl
  var textContentType: UITextContentType?
  // swiftlint:disable:next explicit_acl
  var onSubmit: (() -> Void)?

  @FocusState private var isFocused: Bool

  var body: some View {
    TextField(placeholder, text: $text)
      .font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
      .keyboardType(keyboardType)
      .textContentType(textContentType)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .focused($isFocused)
      .padding(.horizontal, Spacing.contentHorizontal)
      .padding(.vertical, Spacing.sm)
      .onSubmit {
        onSubmit?()
      }
  }
}

// MARK: - Native Secure Field

/// A secure field styled like native iOS grouped forms
struct NativeSecureField: View {
  let placeholder: String
  @Binding var text: String
  // swiftlint:disable:next explicit_acl
  var onSubmit: (() -> Void)?

  @FocusState private var isFocused: Bool
  @State private var isSecure: Bool = true

  var body: some View {
    HStack(spacing: Spacing.sm) {
      if isSecure {
        SecureField(placeholder, text: $text)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .textContentType(.password)
          .focused($isFocused)
          .onSubmit {
            onSubmit?()
          }
      } else {
        TextField(placeholder, text: $text)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .textContentType(.password)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($isFocused)
          .onSubmit {
            onSubmit?()
          }
      }

      visibilityToggle
    }
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.vertical, Spacing.sm)
  }

  private var visibilityToggle: some View {
    Button {
      isSecure.toggle()
    } label: {
      Image(systemName: isSecure ? "eye" : "eye.slash")
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextMuted)
        .frame(minWidth: 44, minHeight: 44)  // swiftlint:disable:this no_magic_numbers
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isSecure ? Text(.authPasswordShow) : Text(.authPasswordHide))
    // Let the 44pt target extend into the row padding without making the row taller
    .padding(.vertical, -Spacing.sm)
  }
}

// MARK: - Snappy Button Style

/// Button style with immediate press feedback
struct SnappyButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
      .opacity(configuration.isPressed ? 0.9 : 1.0)
      .motionAnimation(.affordance, value: configuration.isPressed, reduceMotion: reduceMotion)
  }
}
