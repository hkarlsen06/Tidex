import SwiftUI
import UIKit
import os

private let launchLog = Logger(subsystem: "no.tidex.app", category: "Launch")

extension Notification.Name {
  static let debugRestartPreAuthOnboarding = Notification.Name("debugRestartPreAuthOnboarding")
}

/// Root view wrapper that ensures a seamless launch experience.
///
/// The first SwiftUI frame renders a lightweight `LoadingView` that only depends
/// on cached appearance state. This guarantees the frame is committed before iOS
/// removes the launch storyboard, preventing the black-flash issue that can occur
/// when heavier singletons trigger initialization during the first body evaluation.
///
/// After the initial frame is on screen, `isReady` flips and `RootContent` is
/// created, which initializes `AppCoordinator`, `BiometricAuthService`, etc.
struct RootView: View {
  @State private var isReady = false

  var body: some View {
    if isReady {
      RootContent()
    } else {
      LoadingView()
        .task {
          // The .task fires after the view has appeared on screen.
          // Flipping isReady triggers RootContent creation (with singletons)
          // while LoadingView is already visible — no black gap.
          isReady = true
        }
    }
  }
}

/// Actual root content that manages the app's navigation based on authentication state.
/// Handles transitions between: Loading -> Onboarding -> Login -> MFA -> Post-Auth Onboarding -> Dashboard
private struct RootContent: View {
  // Note: Using @ObservedObject for singletons as @StateObject is meant for owned instances
  @ObservedObject private var coordinator = AppCoordinator.shared
  @ObservedObject private var biometricService = BiometricAuthService.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  // Theme is handled at UIKit window level - no need to observe AppearanceManager here

  // Onboarding state - explicit naming for two-phase onboarding
  @AppStorage("hasCompletedPreAuthOnboarding") private var hasCompletedPreAuthOnboarding = false
  @AppStorage("hasCompletedPostAuthOnboarding") private var hasCompletedPostAuthOnboarding = false

  // Navigation state for transitioning from onboarding to auth
  @State private var showAuthAfterOnboarding = false
  @State private var authDestination: AuthDestination = .login

  // Storage warning state - shown when LocalStore falls back to in-memory storage
  @State private var showStorageWarning = false
  @State private var activeChatToast: InAppChatToastPayload?
  @State private var chatToastDismissTask: Task<Void, Never>?

  enum AuthDestination {
    case login
    case signup
  }

  var body: some View {
    let postAuthOnboardingPresentation = coordinator.currentPostAuthOnboardingPresentation(
      hasCompletedLocally: hasCompletedPostAuthOnboarding
    )

    ZStack {
      // Background - adapts to system appearance
      // Uses tidexBackground (adaptive) for main content areas
      Color.tidexBackground
        .ignoresSafeArea()

      // Content based on app state
      Group {
        switch coordinator.appState {
        case .loading:
          LoadingView()

        case .unauthenticated:
          if !hasCompletedPreAuthOnboarding && !showAuthAfterOnboarding {
            // Show pre-auth onboarding (screens 1-4)
            OnboardingView(
              onComplete: {
                hasCompletedPreAuthOnboarding = true
              },
              onNavigateToSignup: {
                authDestination = .signup
                showAuthAfterOnboarding = true
              },
              onNavigateToLogin: {
                authDestination = .login
                showAuthAfterOnboarding = true
              }
            )
            .transition(.opacity)
          } else {
            // Show auth navigation with the selected destination
            AuthNavigationView(initialScreen: authDestination == .signup ? .signup : .login)
              .transition(.opacity)
          }

        case .mfaRequired:
          if let factor = coordinator.pendingMFAFactor {
            MFAVerifyView(factor: factor, coordinator: coordinator)
              .transition(.opacity)
          } else {
            // Fallback - shouldn't happen
            AuthNavigationView()
          }

        case .termsRequired:
          AcceptTermsView(isUpdate: coordinator.isTermsUpdate, coordinator: coordinator)
            .transition(.opacity)

        case .authenticated:
          if let entryMode = postAuthOnboardingPresentation.entryMode {
            PostAuthOnboardingView(
              entryMode: entryMode,
              onComplete: {
                hasCompletedPostAuthOnboarding = true
                coordinator.dismissPostAuthOnboarding(markCompletedRemotely: true)
              },
              onClose: {
                coordinator.dismissPostAuthOnboarding()
              },
              userId: coordinator.userId ?? ""
            )
            .transition(.opacity)
          } else {
            MainTabView()
              .overlay {
                if biometricService.isLocked {
                  AppLockView()
                    .transition(.opacity)
                }
              }
              .overlay(alignment: .top) {
                if let activeChatToast {
                  InAppChatToastView(
                    payload: activeChatToast,
                    onTap: {
                      dismissChatToast()
                      coordinator.pendingDeepLink = .friendChat(
                        threadId: activeChatToast.threadId,
                        messageId: activeChatToast.messageId,
                        senderUserId: activeChatToast.senderUserId
                      )
                    },
                    onDismiss: {
                      dismissChatToast()
                    }
                  )
                  .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                  .padding(.horizontal, Spacing.md)
                  .padding(.top, 8)
                  .transition(.move(edge: .top).combined(with: .opacity))
                  .zIndex(10)
                }
              }
          }
        }
      }
    }
    .motionAnimation(
      .pageTransition, value: hasCompletedPreAuthOnboarding, reduceMotion: reduceMotion
    )
    .motionAnimation(
      .pageTransition, value: hasCompletedPostAuthOnboarding, reduceMotion: reduceMotion
    )
    .motionAnimation(.subtle, value: biometricService.isLocked, reduceMotion: reduceMotion)
    .environmentObject(coordinator)
    // Theme is handled at UIKit window level via AppearanceManager.applyToWindows()
    // Don't use .preferredColorScheme() here as it conflicts with window.overrideUserInterfaceStyle
    .onAppear {
      launchLog.info(
        "[Launch] RootContent.onAppear – appState=\(String(describing: coordinator.appState))")
      coordinator.refreshPostAuthOnboardingPresentation(
        hasCompletedLocally: hasCompletedPostAuthOnboarding
      )
    }
    .onAppear {
      Task { @MainActor in
        // Defer storage initialization until after first render to avoid launch stalls.
        await Task.yield()
        if LocalStore.shared.isUsingInMemoryFallback {
          showStorageWarning = true
        }
      }
    }
    .alert(String(localized: .alertsStorageIssueTitle), isPresented: $showStorageWarning) {
      Button(String(localized: .alertsOk), role: .cancel) {}
    } message: {
      Text(.alertsStorageIssueMessage)
    }
    .onReceive(NotificationCenter.default.publisher(for: .debugRestartPreAuthOnboarding)) { _ in
      hasCompletedPreAuthOnboarding = false
      showAuthAfterOnboarding = false
      authDestination = .login
    }
    .onReceive(NotificationCenter.default.publisher(for: .inAppChatToastRequested)) {
      notification in
      guard coordinator.appState == .authenticated,
        let payload = notification.object as? InAppChatToastPayload
      else {
        return
      }

      showChatToast(payload)
    }
    .onChange(of: coordinator.appState) { _, _ in
      coordinator.refreshPostAuthOnboardingPresentation(
        hasCompletedLocally: hasCompletedPostAuthOnboarding
      )
    }
    .onChange(of: coordinator.hasFinishedOnboardingRemotely) { _, _ in
      coordinator.refreshPostAuthOnboardingPresentation(
        hasCompletedLocally: hasCompletedPostAuthOnboarding
      )
    }
    .onChange(of: hasCompletedPostAuthOnboarding) { _, newValue in
      coordinator.refreshPostAuthOnboardingPresentation(hasCompletedLocally: newValue)
    }
    .onDisappear {
      chatToastDismissTask?.cancel()
      chatToastDismissTask = nil
    }
  }

  private func showChatToast(_ payload: InAppChatToastPayload) {
    chatToastDismissTask?.cancel()
    withAnimation(.spring(duration: 0.32, bounce: 0.14)) {
      activeChatToast = payload
    }

    chatToastDismissTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      dismissChatToast()
    }
  }

  private func dismissChatToast() {
    chatToastDismissTask?.cancel()
    chatToastDismissTask = nil
    withAnimation(.spring(duration: 0.28, bounce: 0.08)) {
      activeChatToast = nil
    }
  }
}

// MARK: - Loading View

/// Initial loading view shown while checking authentication state
/// Matches the splash screen exactly, with a spinner below the logo
struct LoadingView: View {
  @ObservedObject private var appearanceManager = AppearanceManager.shared
  @Environment(\.colorScheme) private var systemColorScheme

  private var launchBackgroundColor: Color {
    let userInterfaceStyle: UIUserInterfaceStyle

    switch appearanceManager.theme.resolvedColorScheme(fallback: systemColorScheme) {
    case .light:
      userInterfaceStyle = .light
    case .dark:
      userInterfaceStyle = .dark
    @unknown default:
      userInterfaceStyle = .light
    }

    let traits = UITraitCollection(userInterfaceStyle: userInterfaceStyle)
    if let color = UIColor(named: "LaunchBackground", in: .main, compatibleWith: traits) {
      return Color(uiColor: color)
    }

    return .tidexLaunchBackground
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // Use the cached app theme so the first SwiftUI frame matches the
        // user's last-selected appearance as early as possible.
        launchBackgroundColor

        // Logo centered in full screen (ignoring safe areas) - matches storyboard centerX/centerY
        Image("SplashLaunch")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 150, height: 150)
          .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

        // Spinner positioned below the logo
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
          .scaleEffect(1.2)
          .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 105)
      }
    }
    .ignoresSafeArea()
    .onAppear {
      launchLog.info("[Launch] LoadingView.onAppear – first SwiftUI frame visible")
    }
  }
}

#Preview("Root View") {
  RootView()
}

#Preview("Loading View") {
  ZStack {
    Color.tidexBackground.ignoresSafeArea()
    LoadingView()
  }
}
