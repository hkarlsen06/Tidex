import SwiftUI

/// Styled text field with Tidex design
/// Supports placeholder, label, and error state
struct TidexTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var error: String? = nil
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrection: Bool = true
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            // Text field
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(!autocorrection)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.tidexSurfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
                .cornerRadius(10)
                .onSubmit {
                    onSubmit?()
                }

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
        TidexTextField(
            label: "Email",
            placeholder: "name@example.com",
            text: .constant("")
        )

        TidexTextField(
            label: "Email",
            placeholder: "name@example.com",
            text: .constant("test@example.com")
        )

        TidexTextField(
            label: "Email",
            placeholder: "name@example.com",
            text: .constant("invalid"),
            error: "Invalid email format"
        )
    }
    .padding()
    .background(Color.tidexDarkBackground)
}
