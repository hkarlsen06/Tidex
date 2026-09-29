import Foundation

extension ProfileSettingsViewModel {
  /// Keep the saved avatar usable until persistence succeeds. A thrown save
  /// may leave pending model changes, so preserve both files in that case.
  static func commitAvatarChange(
    from previousURL: String?,
    to newURL: String?,
    persist: () async throws -> Bool,
    removeStoredAvatar: (String) async -> Void
  ) async throws {
    guard try await persist() else {
      // Missing settings means no model was changed, so the new file is orphaned.
      if let newURL, newURL != previousURL {
        await removeStoredAvatar(newURL)
      }
      throw LocalStoreWriteError.notFound
    }

    if let previousURL, previousURL != newURL {
      await removeStoredAvatar(previousURL)
    }
  }
}
