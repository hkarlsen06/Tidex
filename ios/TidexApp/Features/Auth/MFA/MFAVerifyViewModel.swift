import Foundation
import SwiftUI

/// View model for MFA verification screen
@MainActor
final class MFAVerifyViewModel: ObservableObject {

  // MARK: - Dependencies

  let factor: AuthService.MFAFactor
  private let authService: AuthService
  private weak var coordinator: AppCoordinator?

  // MARK: - Published State

  @Published var code: String = ""
  @Published var isLoading = false
  @Published var isVerificationComplete = false  // Keeps overlay visible during transition
  @Published var errorMessage: String?
  @Published var focusedIndex: Int = 0

  // MARK: - Private State

  private var challengeId: String?
  private var verifyTask: Task<Void, Never>?

  // MARK: - Initialization

  init(
    factor: AuthService.MFAFactor,
    coordinator: AppCoordinator,
    authService: AuthService? = nil,
  ) {
    self.factor = factor
    self.coordinator = coordinator
    self.authService = authService ?? AuthService.shared
  }

  deinit {
    verifyTask?.cancel()
  }

  // MARK: - Computed Properties

  /// Get the digit at a specific index
  func digit(at index: Int) -> String {
    guard index < code.count else { return "" }
    let codeIndex = code.index(code.startIndex, offsetBy: index)
    return String(code[codeIndex])
  }

  // MARK: - Actions

  /// Create MFA challenge on view appear
  func createChallenge() async {
    isLoading = true
    defer { isLoading = false }

    do {
      challengeId = try await authService.createMFAChallenge(factorId: factor.id)
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  /// Handle code input changes
  func handleCodeChange(_ newValue: String) {
    // Only allow digits
    let filtered = newValue.filter { $0.isNumber }

    // Limit to 6 characters
    if filtered.count > 6 {
      code = String(filtered.prefix(6))
    } else {
      code = filtered
    }

    // Update focused index
    focusedIndex = min(code.count, 5)

    // Auto-submit when 6 digits entered
    if code.count == 6 {
      // Cancel any existing verify task to prevent concurrent attempts
      verifyTask?.cancel()
      verifyTask = Task { await verifyCode() }
    }
  }

  /// Verify the MFA code
  func verifyCode() async {
    guard code.count == 6 else {
      errorMessage = String(localized: .mfaErrorsCodeRequired)
      return
    }

    guard let challengeId = challengeId else {
      errorMessage = String(localized: .mfaErrorsChallengeExpired)
      // Try to create a new challenge
      await createChallenge()
      return
    }

    // Dismiss keyboard immediately for smoother transition
    _ = await MainActor.run {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil, from: nil, for: nil
      )
    }

    isLoading = true

    do {
      try await authService.verifyMFA(
        factorId: factor.id,
        challengeId: challengeId,
        code: code
      )

      // MFA verified successfully - play hold haptic for satisfying feedback
      Haptics.play(.hold)

      // Keep overlay visible during transition
      isLoading = false
      isVerificationComplete = true

      // MFA verified successfully
      coordinator?.handleMFASuccess()
    } catch {
      isLoading = false
      errorMessage = ErrorTranslations.translate(error)
      // Clear the code on error
      code = ""
      focusedIndex = 0
    }
  }

  /// Sign out and return to login
  func signOutAndReturn() async {
    await coordinator?.signOut()
  }
}
