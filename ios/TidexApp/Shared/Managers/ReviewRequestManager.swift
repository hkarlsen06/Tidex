import Foundation

@MainActor
final class ReviewRequestManager {
  static let shared = ReviewRequestManager()

  private static let minShiftCount = 5
  private static let minAccountAgeDays = 14
  private static let cooldownDays = 120

  private init() {}

  func requestReviewIfEligible(
    userId: String,
    requestReview: @MainActor () -> Void
  ) {
    guard !userId.isEmpty else { return }
    guard isPastCooldown(for: userId) else { return }

    let shiftCount = ShiftsRepository.shared.getAllShifts(for: userId).count
    guard shiftCount >= Self.minShiftCount else { return }

    if let createdAt = SettingsRepository.shared.getSettings(for: userId)?.created_at,
      let createdDate = Self.parseISO8601Date(createdAt)
    {
      let accountAgeDays =
        Calendar.current.dateComponents([.day], from: createdDate, to: Date()).day ?? 0
      guard accountAgeDays >= Self.minAccountAgeDays else { return }
    }

    requestReview()
    UserDefaults.standard.set(Date(), forKey: reviewRequestedKey(for: userId))
  }

  private func reviewRequestedKey(for userId: String) -> String {
    "review_requested.\(userId)"
  }

  private func isPastCooldown(for userId: String) -> Bool {
    guard
      let lastRequested = UserDefaults.standard.object(forKey: reviewRequestedKey(for: userId))
        as? Date
    else {
      return true
    }

    let daysSinceLastRequest =
      Calendar.current.dateComponents([.day], from: lastRequested, to: Date()).day ?? 0
    return daysSinceLastRequest >= Self.cooldownDays
  }

  private static func parseISO8601Date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = formatter.date(from: value) {
      return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}
