import SwiftUI

/// Full-screen lock overlay shown when biometric lock is enabled and app is locked
struct AppLockView: View {
  @ObservedObject private var biometricService = BiometricAuthService.shared
  @Environment(\.scenePhase) private var scenePhase

  @State private var isAuthenticating = false
  @State private var wasInBackground = false

  var body: some View {
    ZStack {
      Color.tidexLaunchBackground

      VStack(spacing: 0) {
        Spacer()

        // App logo
        Image("Splash")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120, height: 120)

        Spacer()
          .frame(height: 24)

        // Title
        Text(.appLockTitle)
          .font(.title3)
          .fontWeight(.semibold)
          .foregroundColor(.tidexTextPrimary)

        Spacer()
          .frame(height: 8)

        // Subtitle
        Text(.appLockSubtitle)
          .font(.subheadline)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 48)

        Spacer()

        // Tappable biometric icon — Apple-style
        Button {
          Task { await unlock() }
        } label: {
          VStack(spacing: 10) {
            if isAuthenticating {
              ProgressView()
                .controlSize(.regular)
                .tint(.tidexTextSecondary)
            } else {
              Image(systemName: biometricService.biometricIconName)
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(.tidexTextPrimary)
                .contentTransition(.symbolEffect(.replace))
            }

            Text(String(localized: .appLockUnlock(biometricService.biometricTypeName)))
              .font(.footnote)
              .foregroundColor(.tidexTextSecondary)
          }
        }
        .disabled(isAuthenticating)

        Spacer()
          .frame(height: 80)
      }
    }
    .ignoresSafeArea()
    .task {
      await unlock()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .background {
        wasInBackground = true
      } else if newPhase == .active, wasInBackground {
        wasInBackground = false
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
