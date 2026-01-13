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
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(label)
                .font(.system(size: 14, weight: .medium))
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
                .font(.system(size: 16))
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
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.tidexSurfaceSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(10)

            // Error message
            if let error = error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
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
    VStack(spacing: 24) {
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
    .background(Color.tidexDarkBackground)
}
