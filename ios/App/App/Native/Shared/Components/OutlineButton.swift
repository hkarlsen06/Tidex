import SwiftUI

/// Secondary/outline button with Tidex styling
/// Used for secondary actions and expandable options
struct OutlineButton: View {
    let title: String
    let action: () -> Void
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextSecondary))
                        .scaleEffect(0.8)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }

                Text(title)
                    .font(.system(size: 16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundColor(.tidexTextSecondary)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.tidexBorder, lineWidth: 1)
            )
        }
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

#Preview {
    VStack(spacing: 16) {
        OutlineButton(title: "Log in with email or phone", action: {})

        OutlineButton(title: "With Icon", action: {}, icon: "envelope")

        OutlineButton(title: "Loading", action: {}, isLoading: true)
    }
    .padding()
    .background(Color.tidexDarkBackground)
}
