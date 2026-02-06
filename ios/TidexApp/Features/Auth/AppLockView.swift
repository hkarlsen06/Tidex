import SwiftUI

/// Full-screen lock overlay shown when biometric lock is enabled and app is locked
struct AppLockView: View {
    @ObservedObject private var biometricService = BiometricAuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var isAuthenticating = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - matches splash screen
                Color.tidexLaunchBackground

                VStack(spacing: 32) {
                    Spacer()

                    // Logo
                    Image("Splash")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)

                    // Lock icon and text
                    VStack(spacing: 12) {
                        Image(systemName: biometricService.biometricIconName)
                            .font(.system(size: 44))
                            .foregroundColor(.tidexBlue)

                        Text(.appLockTitle)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.tidexTextPrimary)

                        Text(.appLockSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.tidexTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer()

                    // Unlock button
                    Button {
                        Task {
                            await unlock()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: biometricService.biometricIconName)
                                    .font(.system(size: 20))
                            }
                            Text(String(localized: .appLockUnlock(biometricService.biometricTypeName)))
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.tidexBlue)
                        .cornerRadius(12)
                    }
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 60)
                }
            }
        }
        .ignoresSafeArea()
        .task {
            // Auto-trigger biometric prompt on appear (fresh launch)
            await unlock()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-trigger biometric prompt when returning from background.
            // .task only fires on first appear; if the view was inserted while
            // backgrounded, it won't re-fire when the app becomes active.
            if newPhase == .active {
                Task { await unlock() }
            }
        }
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        _ = await biometricService.authenticate()
        isAuthenticating = false
    }
}

#Preview {
    AppLockView()
}
