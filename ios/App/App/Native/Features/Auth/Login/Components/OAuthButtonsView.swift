import SwiftUI

/// OAuth sign-in buttons for Google and Apple
struct OAuthButtonsView: View {
    let onGoogleTap: () -> Void
    let onAppleTap: () -> Void
    var isLoading: Bool = false

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 12) {
            // Apple Sign-In Button
            Button(action: onAppleTap) {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .medium))

                    Text(localization.string("oauth.continueWithApple"))
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundColor(.white)
                .background(Color.black)
                .cornerRadius(10)
            }
            .disabled(isLoading)

            // Google Sign-In Button
            Button(action: onGoogleTap) {
                HStack(spacing: 12) {
                    // Google logo (simplified)
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.red)

                    Text(localization.string("oauth.continueWithGoogle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white)
                .cornerRadius(10)
            }
            .disabled(isLoading)
        }
    }
}

#Preview {
    OAuthButtonsView(
        onGoogleTap: {},
        onAppleTap: {}
    )
    .padding()
    .background(Color.tidexDarkBackground)
}
