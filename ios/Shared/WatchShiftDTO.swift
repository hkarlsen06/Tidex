// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl
import Foundation

/// Lightweight shift data for Watch display
struct WatchShiftDTO: Codable, Identifiable, Sendable, Equatable {
  let id: String
  let personId: String
  let personName: String
  let personProfilePictureUrl: String?
  let personOauthAvatarUrl: String?
  let shiftDate: String  // "YYYY-MM-DD"
  let startTime: String  // "HH:mm"
  let endTime: String  // "HH:mm"
  let status: ShiftPreviewStatus  // active, upcoming, past

  /// Pre-downloaded avatar image data (JPEG format)
  /// iOS downloads and converts images to avoid watchOS WebP issues
  let avatarImageData: Data?

  /// Resolved avatar URL (profile picture takes precedence over OAuth)
  /// Used as fallback if avatarImageData is nil
  var effectiveAvatarURL: URL? {
    if let urlString = personProfilePictureUrl ?? personOauthAvatarUrl,
      !urlString.isEmpty
    {
      return URL(string: urlString)
    }
    return nil
  }

  /// Check if we have pre-downloaded avatar data
  var hasAvatarData: Bool {
    avatarImageData?.isEmpty == false
  }
}
