import Foundation
import Supabase

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

  static func isUsernameTaken(_ error: PostgrestError) -> Bool {
    if error.code == "23505" {
      return true
    }

    let message = "\(error.message) \(error.localizedDescription)".lowercased()
    return message.contains("duplicate") || message.contains("unique")
  }

  static func isUsernameCheckConstraintViolation(_ error: PostgrestError) -> Bool {
    guard error.code == "23514" else { return false }

    let message = "\(error.message) \(error.localizedDescription)".lowercased()
    return message.contains("profiles_username_format")
      || message.contains("check constraint")
      || message.contains("violates check")
  }

  static func isUsernameSafetyFilterViolation(_ error: PostgrestError) -> Bool {
    let message = "\(error.message) \(error.localizedDescription)".lowercased()
    return message.contains("profiles_username_safety_filter")
      || message.contains("safety filter")
      || message.contains("objectionable")
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
