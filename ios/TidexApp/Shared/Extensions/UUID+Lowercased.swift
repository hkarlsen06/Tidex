import Foundation

extension UUID {
  /// The UUID in lowercase. `uuidString` is uppercase, but the backend and SwiftData store
  /// lowercase ids.
  var lowercasedString: String {
    uuidString.lowercased()
  }
}
