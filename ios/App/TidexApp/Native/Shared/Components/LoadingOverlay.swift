import SwiftUI

/// Full-screen loading overlay with smooth animations
/// Used during async operations like login
struct LoadingOverlay: View {
    var message: String? = nil
    var isSuccess: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if isSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.tidexSuccess)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }

                if let message = message {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextPrimary)
                }
            }
            .padding(32)
            .background(Color.tidexSurfacePrimary.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: isSuccess)
        }
    }
}

/// View modifier for applying loading overlay with smooth transitions
struct LoadingModifier: ViewModifier {
    let isLoading: Bool
    var isSuccess: Bool = false
    var message: String? = nil

    private var showOverlay: Bool {
        isLoading || isSuccess
    }

    func body(content: Content) -> some View {
        ZStack {
            content

            if showOverlay {
                LoadingOverlay(message: message, isSuccess: isSuccess)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.95))
                    )
            }
        }
        .animation(.easeOut(duration: 0.2), value: showOverlay)
        .animation(.easeOut(duration: 0.2), value: isSuccess)
    }
}

extension View {
    /// Apply a loading overlay to the view with smooth transitions
    func loading(_ isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingModifier(isLoading: isLoading, message: message))
    }

    /// Apply a loading overlay that transitions to a success state
    func loadingWithSuccess(_ isLoading: Bool, isSuccess: Bool, message: String? = nil) -> some View {
        modifier(LoadingModifier(isLoading: isLoading, isSuccess: isSuccess, message: message))
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
