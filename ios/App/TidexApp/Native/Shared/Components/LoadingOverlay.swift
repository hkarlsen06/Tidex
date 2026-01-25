import SwiftUI

/// Full-screen loading overlay with smooth animations
/// Used during async operations like login
struct LoadingOverlay: View {
    var message: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                if let message = message {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextPrimary)
                }
            }
            .padding(32)
            .background(Color.tidexSurfacePrimary.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// View modifier for applying loading overlay with smooth transitions
struct LoadingModifier: ViewModifier {
    let isLoading: Bool
    var message: String? = nil

    func body(content: Content) -> some View {
        ZStack {
            content

            if isLoading {
                LoadingOverlay(message: message)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.95))
                    )
            }
        }
        .animation(.easeOut(duration: 0.2), value: isLoading)
    }
}

extension View {
    /// Apply a loading overlay to the view with smooth transitions
    func loading(_ isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingModifier(isLoading: isLoading, message: message))
    }
}

#Preview {
    ZStack {
        Color.tidexBackground.ignoresSafeArea()

        Text("Content behind overlay")
            .foregroundColor(.tidexTextPrimary)
    }
    .loading(true, message: "Logging in...")
}
