import SwiftUI

/// Primary action button with Tidex brand styling
/// Used for main CTAs like "Log in", "Sign up", etc.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                isDisabled
                    ? Color.tidexBrandPrimary.opacity(0.5)
                    : Color.tidexBrandPrimary
            )
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(isDisabled || isLoading)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

/// Loading button that shows a spinner while loading
struct LoadingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        PrimaryButton(
            title: title,
            action: action,
            isLoading: isLoading
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Log in", action: {})

        PrimaryButton(title: "Loading...", action: {}, isLoading: true)

        PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
    .background(Color.tidexDarkBackground)
}
