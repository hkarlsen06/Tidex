// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl file_name
import Foundation
import Supabase

// MARK: - User ID Extension

/// Extension to provide consistent, normalized user ID handling
/// IMPORTANT: Always use these extensions when accessing user IDs to ensure
/// case consistency between Supabase (which returns uppercase UUIDs) and
/// SwiftData (which stores lowercase UUIDs).
extension User {
  /// Returns the user ID as a lowercase string
  /// Use this instead of `id.uuidString` to ensure consistency with SwiftData storage
  var normalizedId: String {
    id.uuidString.lowercased()
  }
}

extension Session {
  /// Returns the user ID as a lowercase string
  /// Use this instead of `user.id.uuidString` to ensure consistency with SwiftData storage
  var normalizedUserId: String {
    user.id.uuidString.lowercased()
  }
}

// MARK: - UUID Extension

extension UUID {
  /// Returns the UUID as a lowercase string
  /// Swift's `uuidString` returns uppercase, but PostgreSQL/Supabase stores lowercase
  var lowercasedString: String {
    uuidString.lowercased()
  }
}
