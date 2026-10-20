import Foundation

internal enum AuthIdentityInput {
  /// True for text that looks like an email address. Clerk checks the rest.
  internal static func isEmail(_ value: String) -> Bool {
    let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.contains("@") && trimmed.contains(".")
  }
}
