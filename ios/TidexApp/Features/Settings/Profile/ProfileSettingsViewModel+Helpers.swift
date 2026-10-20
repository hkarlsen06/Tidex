import Foundation

// MARK: - Helpers

extension ProfileSettingsViewModel {
  static func normalizeUsername(_ username: String) -> String {
    sanitizeUsernameInput(username.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  static func sanitizeUsernameInput(_ username: String) -> String {
    username
      .lowercased()
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
  }

  static func isValidUsername(_ username: String) -> Bool {
    guard (3...20).contains(username.count) else { return false }
    guard username.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil else {
      return false
    }
    return username.range(of: "[a-z]", options: .regularExpression) != nil
  }

  /// Get initials from display name or email
  var initials: String {
    let name = displayName.isEmpty ? email : displayName
    return
      name
      .split(separator: " ")
      .compactMap(\.first)
      .prefix(2)
      .map { String($0).uppercased() }
      .joined()
  }

  /// Clear messages
  func clearMessages() {
    errorMessage = nil
  }
}
