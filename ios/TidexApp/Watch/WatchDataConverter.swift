import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WatchDataConverter")

/// Converts iOS app data to Watch-compatible DTOs
/// Uses local repositories to build a payload for Watch Connectivity
@MainActor
enum WatchDataConverter {

  /// Avatar image size for Watch (small to minimize data transfer)
  private static let avatarSize: CGFloat = 48

  /// JPEG compression quality (0.0-1.0)
  private static let jpegQuality: CGFloat = 0.7

  /// Build a complete payload for the Watch from current app state
  /// Downloads and converts avatar images to JPEG for Watch compatibility
  /// - Parameter userId: The current user's ID
  /// - Returns: WatchDataPayload ready to send via WCSession
  static func buildPayload(for userId: String) async -> WatchDataPayload {
    // Get user settings for currency
    let settings = SettingsRepository.shared.getSettings(for: userId)
    let currencySymbol = settings?.currency ?? "kr"

    // Get last sync timestamp
    let lastSyncTimestamp = SyncCoordinator.shared.lastSyncedAt

    // Build user's shift (with avatar)
    let userShift = await buildUserShift(userId: userId, settings: settings)

    // Build friend shifts (with avatars)
    let friendShifts = await buildFriendShifts(viewerId: userId)

    return WatchDataPayload(
      timestamp: Date(),
      lastSyncTimestamp: lastSyncTimestamp,
      userShift: userShift,
      friendShifts: friendShifts,
      currencySymbol: currencySymbol
    )
  }

  // MARK: - User Shift

  /// Build the user's most relevant shift (active > upcoming > past)
  private static func buildUserShift(userId: String, settings: UserSettings?) async
    -> WatchShiftDTO? {
    let now = Date()
    let calendar = Calendar.current

    // Get shifts for a reasonable range (today - 1 day to today + 7 days)
    let startDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
    let endDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now

    let shifts = ShiftsRepository.shared.getShifts(
      for: userId, startDate: startDate, endDate: endDate)

    guard !shifts.isEmpty else { return nil }

    // Find the most relevant shift
    var activeShift: ShiftRow?
    var upcomingShift: ShiftRow?
    var pastShift: ShiftRow?

    for shift in shifts {
      let shiftDateString = shift.shift_date
      guard let shiftDate = parseDate(shiftDateString) else { continue }

      let status = determineShiftStatus(
        shiftDate: shiftDate, startTime: shift.start_time, endTime: shift.end_time, now: now)

      switch status {
      case .active:
        if activeShift == nil {
          activeShift = shift
        }
      case .upcoming:
        // Keep the earliest upcoming shift
        if let existingDate = upcomingShift.flatMap({ parseDate($0.shift_date) }),
          shiftDate < existingDate {
          upcomingShift = shift
        } else if upcomingShift == nil {
          upcomingShift = shift
        }
      case .past:
        // Keep the most recent past shift
        if let existingDate = pastShift.flatMap({ parseDate($0.shift_date) }),
          shiftDate > existingDate {
          pastShift = shift
        } else if pastShift == nil {
          pastShift = shift
        }
      }
    }

    // Priority: active > upcoming > past
    let selectedShift = activeShift ?? upcomingShift ?? pastShift
    guard let shift = selectedShift,
      let shiftDate = parseDate(shift.shift_date)
    else { return nil }

    let status = determineShiftStatus(
      shiftDate: shiftDate, startTime: shift.start_time, endTime: shift.end_time, now: now)

    // Get user display name
    let displayName = AppCoordinator.shared.userDisplayName

    // Download user's avatar
    let avatarData = await downloadAvatar(from: settings?.profile_picture_url)

    return WatchShiftDTO(
      id: shift.id,
      personId: userId,
      personName: displayName,
      personProfilePictureUrl: settings?.profile_picture_url,
      personOauthAvatarUrl: nil,
      shiftDate: shift.shift_date,
      startTime: shift.start_time,
      endTime: shift.end_time,
      status: status,
      avatarImageData: avatarData
    )
  }

  // MARK: - Friend Shifts

  /// Build friend shifts from cached sharing data
  private static func buildFriendShifts(viewerId: String) async -> [WatchShiftDTO] {
    // Get cached sharers (non-blocked)
    let sharers = SharedShiftsRepository.shared.getSharers(for: viewerId)

    // Get cached shift previews
    let previewMap = SharedShiftsRepository.shared.getShiftPreviews(for: viewerId)

    // Download avatars concurrently
    var friendShifts: [WatchShiftDTO] = []

    // Use TaskGroup for concurrent avatar downloads
    await withTaskGroup(of: WatchShiftDTO?.self) { group in
      for sharer in sharers {
        guard let preview = previewMap[sharer.id],
          let shift = preview.shift,
          let localStatus = preview.status
        else {
          continue
        }

        group.addTask {
          // Prefer profile picture, fall back to OAuth avatar
          let avatarUrl = sharer.profilePictureUrl ?? sharer.oauthAvatarUrl
          let avatarData = await downloadAvatar(from: avatarUrl)

          return WatchShiftDTO(
            id: "\(sharer.id)_\(shift.id)",
            personId: sharer.id,
            personName: sharer.firstName ?? sharer.displayName,
            personProfilePictureUrl: sharer.profilePictureUrl,
            personOauthAvatarUrl: sharer.oauthAvatarUrl,
            shiftDate: shift.shift_date,
            startTime: shift.start_time,
            endTime: shift.end_time,
            status: localStatus,
            avatarImageData: avatarData
          )
        }
      }

      for await dto in group {
        if let dto = dto {
          friendShifts.append(dto)
        }
      }
    }

    // Sort: active first, then upcoming, then past
    friendShifts.sort { lhs, rhs in
      let lhsPriority = statusPriority(lhs.status)
      let rhsPriority = statusPriority(rhs.status)
      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }
      // Within same status, sort by date/time
      return lhs.shiftDate < rhs.shiftDate
    }

    return friendShifts
  }

  // MARK: - Avatar Download

  /// Download an avatar image and convert to JPEG data for Watch compatibility
  /// - Parameter urlString: The URL string of the avatar image
  /// - Returns: JPEG data or nil if download/conversion fails
  private static func downloadAvatar(from urlString: String?) async -> Data? {
    guard let urlString = urlString,
      !urlString.isEmpty,
      let url = URL(string: urlString)
    else {
      return nil
    }

    do {
      let (data, response) = try await URLSession.shared.data(from: url)

      // Verify we got a valid response
      guard let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200
      else {
        logger.warning("Avatar download failed for \(urlString): bad response")
        return nil
      }

      // Convert to UIImage
      guard let image = UIImage(data: data) else {
        logger.warning("Avatar conversion failed for \(urlString): invalid image data")
        return nil
      }

      // Resize and convert to JPEG
      let resizedImage = resizeImage(image, to: avatarSize)
      guard let jpegData = resizedImage.jpegData(compressionQuality: jpegQuality) else {
        logger.warning("Avatar JPEG conversion failed for \(urlString)")
        return nil
      }

      logger.info("Avatar downloaded: \(urlString) (\(jpegData.count) bytes)")
      return jpegData

    } catch {
      logger.error("Avatar download error for \(urlString): \(error.localizedDescription)")
      return nil
    }
  }

  /// Resize an image to fit within a square of the given size
  private static func resizeImage(_ image: UIImage, to size: CGFloat) -> UIImage {
    let targetSize = CGSize(width: size, height: size)

    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  // MARK: - Helpers

  /// Parse a date string in "YYYY-MM-DD" format
  private static func parseDate(_ dateString: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: dateString)
  }

  /// Determine the status of a shift based on current time
  /// Returns the shared ShiftPreviewStatus enum for Watch compatibility
  private static func determineShiftStatus(
    shiftDate: Date, startTime: String, endTime: String, now: Date
  ) -> ShiftPreviewStatus {
    let calendar = Calendar.current

    // Parse start time
    let startParts = startTime.split(separator: ":").compactMap { Int($0) }
    guard startParts.count >= 2 else { return .past }

    var startComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    startComponents.hour = startParts[0]
    startComponents.minute = startParts[1]

    guard let shiftStart = calendar.date(from: startComponents) else { return .past }

    // Parse end time
    let endParts = endTime.split(separator: ":").compactMap { Int($0) }
    guard endParts.count >= 2 else { return .past }

    var endComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    endComponents.hour = endParts[0]
    endComponents.minute = endParts[1]

    var shiftEnd = calendar.date(from: endComponents) ?? shiftStart

    // Handle cross-midnight shifts
    if shiftEnd <= shiftStart {
      shiftEnd = calendar.date(byAdding: .day, value: 1, to: shiftEnd) ?? shiftEnd
    }

    // Determine status
    if now >= shiftStart && now < shiftEnd {
      return .active
    } else if now < shiftStart {
      return .upcoming
    } else {
      return .past
    }
  }

  /// Sort priority (lower = higher priority)
  private static func statusPriority(_ status: ShiftPreviewStatus) -> Int {
    switch status {
    case .active: return 0
    case .upcoming: return 1
    case .past: return 2
    }
  }
}
