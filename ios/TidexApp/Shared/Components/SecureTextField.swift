import SwiftUI

/// Styled secure text field for passwords
/// Includes toggle to show/hide password
struct SecureTextField: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  var error: String? = nil
  var onSubmit: (() -> Void)? = nil

  @State private var isSecure = true
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      // Label
      Text(label)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      // Field with toggle
      HStack(spacing: 0) {
        Group {
          if isSecure {
            SecureField(placeholder, text: $text)
              .textContentType(.password)
          } else {
            TextField(placeholder, text: $text)
              .textContentType(.password)
          }
        }
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
        .focused($isFocused)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit {
          onSubmit?()
        }

        // Show/hide toggle
        Button {
          isSecure.toggle()
        } label: {
          Image(systemName: isSecure ? "eye" : "eye.slash")
            .foregroundColor(.tidexTextMuted)
            .font(.tidexBody)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.md)
          .stroke(borderColor, lineWidth: 1)
      )
      .cornerRadius(CornerRadius.md)
      .contentShape(Rectangle())

      // Error message
      if let error = error, !error.isEmpty {
        Text(error)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexError)
      }
    }
  }

  private var borderColor: Color {
    if error != nil {
      return .tidexError
    }
    if isFocused {
      return .tidexBrandPrimary
    }
    return .tidexBorder
  }
}

#Preview {
  VStack(spacing: Spacing.lg) {
    SecureTextField(
      label: "Password",
      placeholder: "Enter your password",
      text: .constant("")
    )

    SecureTextField(
      label: "Password",
      placeholder: "Enter your password",
      text: .constant("secretpassword")
    )

    SecureTextField(
      label: "Password",
      placeholder: "Enter your password",
      text: .constant("short"),
      error: "Password must be at least 6 characters"
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
