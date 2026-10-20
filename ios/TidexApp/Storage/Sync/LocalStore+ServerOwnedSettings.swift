import Foundation

extension LocalStoreActor {
  /// The profile picture uploads through its own server endpoint, so `user_settings` sync never
  /// sends `profile_picture_url`. The profile screen can still mark it dirty. This removes it
  /// from the dirty set, and a row with nothing else dirty becomes clean, so it does not stay
  /// dirty for ever. The pull applies the server's value.
  func dropServerOwnedSettingsFields(userId: String) {
    guard let existing = try? getUserSettings(userId: userId),
      existing.dirtyFieldKeys.contains(.profilePictureUrl)
    else { return }
    existing.dirtyFieldKeys.remove(.profilePictureUrl)
    if existing.dirtyFieldKeys.isEmpty, existing.syncStatus == .dirty {
      existing.syncStatus = .clean
    }
  }
}
