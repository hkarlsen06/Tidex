import Foundation
import os.log
import Supabase

private enum FeedbackSettingsConstants {
  static var logger: Logger {
    Logger(subsystem: "com.tidex.app", category: "FeedbackSettingsViewModel")
  }

  static let maxFeedbackLength: Int = 2_000
}

// MARK: - Models

/// A feedback item from the database
internal struct FeedbackItem: Codable, Identifiable {
  internal enum CodingKeys: String, CodingKey {
    case createdAt = "created_at"
    case id = "id"
    case message = "message"
    case respondedAt = "responded_at"
    case respondedBy = "responded_by"
    case response = "response"
    case userEmail = "user_email"
    case userId = "user_id"
  }

  internal let id: String
  internal let userId: String
  internal let message: String
  internal let userEmail: String
  internal let createdAt: String
  internal let response: String?
  internal let respondedAt: String?
  internal let respondedBy: String?
}

/// Data for inserting new feedback
internal struct FeedbackInsert: Encodable {
  internal enum CodingKeys: String, CodingKey {
    case message = "message"
    case userEmail = "user_email"
    case userId = "user_id"
  }

  internal let userId: String
  internal let message: String
  internal let userEmail: String
}

// MARK: - View Model

/// ViewModel for feedback settings
@MainActor
internal final class FeedbackSettingsViewModel: ObservableObject {

  // MARK: - Published State

  /// The feedback message being composed
  @Published internal var message: String = ""

  /// Loading state for initial data fetch
  @Published internal var isLoading: Bool = false

  /// Loading state for submitting feedback
  @Published internal var isSubmitting: Bool = false

  /// Error message to display
  @Published internal var errorMessage: String?

  /// Whether feedback was successfully submitted
  @Published internal var showSuccess: Bool = false
  /// Whether feedback actions are unavailable because the session was resolved offline
  @Published internal private(set) var isOfflineUnavailable: Bool = false

  /// History of user's feedback
  @Published internal var feedbackHistory: [FeedbackItem] = []

  /// Currently expanded feedback item ID
  @Published internal var expandedItemId: String?

  // MARK: - Computed Properties

  /// Current character count
  internal var characterCount: Int {
    message.count
  }

  /// Whether the message exceeds the max length
  internal var isOverLimit: Bool {
    message.count > FeedbackSettingsConstants.maxFeedbackLength
  }

  /// Whether the submit button should be enabled
  internal var canSubmit: Bool {
    !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isOverLimit
      && !isSubmitting && !isOfflineUnavailable
  }

  /// Formatted character count string
  internal var characterCountText: String {
    "\(characterCount) / \(FeedbackSettingsConstants.maxFeedbackLength)"
  }

  // MARK: - Private Properties

  private var userId: String?
  private var userEmail: String?

  // MARK: - Initialization

  internal init() {
    // Default initializer required for SwiftLint's explicit initialization policy.
  }

  deinit {
    // Required by SwiftLint.
  }

  // MARK: - Public Methods

  /// Load initial data - user info and feedback history
  internal func loadData() async {
    isLoading = true
    errorMessage = nil
    isOfflineUnavailable = false

    do {
      // Get current user session
      let session: Session = try await AuthSessionManager.shared.getSession()
      userId = session.normalizedUserId
      userEmail = session.user.email ?? ""

      // Fetch feedback history
      await fetchFeedbackHistory()

    } catch {
      FeedbackSettingsConstants.logger.error(
        "Failed to get user session: \(error.localizedDescription)"
      )
      if AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback()
      {
        userId = offlineUserId
        userEmail = ""
        feedbackHistory = []
        isOfflineUnavailable = true
      } else {
        errorMessage = "Not authenticated"
      }
    }

    isLoading = false
  }

  /// Submit new feedback
  internal func submitFeedback() async {
    guard !isOfflineUnavailable else {
      errorMessage = String(localized: .feedbackOfflineSubmitUnavailable)
      return
    }

    guard let userId, let userEmail else {
      errorMessage = "Not authenticated"
      return
    }

    let trimmedMessage: String = message.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedMessage.isEmpty else {
      errorMessage = "Please enter your feedback"
      return
    }

    guard trimmedMessage.count <= FeedbackSettingsConstants.maxFeedbackLength else {
      errorMessage =
        "Feedback must be \(FeedbackSettingsConstants.maxFeedbackLength) characters or less"
      return
    }

    isSubmitting = true
    errorMessage = nil

    do {
      try await submitFeedback(
        userId: userId,
        userEmail: userEmail,
        message: trimmedMessage
      )
      await handleSuccessfulSubmission()
    } catch {
      FeedbackSettingsConstants.logger.error(
        "Failed to submit feedback: \(error.localizedDescription)"
      )
      errorMessage = "Failed to send feedback. Please try again."
    }

    isSubmitting = false
  }

  /// Clear error message
  internal func clearError() {
    errorMessage = nil
  }

  /// Reset success state to show form again
  internal func resetSuccess() {
    showSuccess = false
  }

  /// Toggle expanded state for a feedback item
  internal func toggleExpanded(_ itemId: String) {
    if expandedItemId == itemId {
      expandedItemId = nil
    } else {
      expandedItemId = itemId
    }
  }

  // MARK: - Private Methods

  private func submitFeedback(userId: String, userEmail: String, message: String) async throws {
    let feedback: FeedbackInsert = .init(
      userId: userId,
      message: message,
      userEmail: userEmail
    )

    try await supabase
      .from("feedback")
      .insert(feedback)
      .execute()
  }

  private func handleSuccessfulSubmission() async {
    FeedbackSettingsConstants.logger.info("Feedback submitted successfully")
    message = ""
    showSuccess = true
    await fetchFeedbackHistory()
  }

  /// Fetch user's feedback history
  private func fetchFeedbackHistory() async {
    guard let userId else {
      return
    }

    do {
      let items: [FeedbackItem] =
        try await supabase
        .from("feedback")
        .select()
        .eq("user_id", value: userId)
        .order("created_at", ascending: false)
        .execute()
        .value

      feedbackHistory = items
      FeedbackSettingsConstants.logger.info("Fetched \(items.count) feedback items")

    } catch {
      FeedbackSettingsConstants.logger.error(
        "Failed to fetch feedback history: \(error.localizedDescription)"
      )
      // Don't show error for history fetch failure
    }
  }
}

// MARK: - Date Formatting Helpers

extension FeedbackItem {
  /// Format the created_at date for display
  func formattedDate(locale: Locale) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    guard let date = formatter.date(from: createdAt) else {
      // Try without fractional seconds
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: createdAt) else {
        return createdAt
      }
      return formatDate(date, locale: locale)
    }

    return formatDate(date, locale: locale)
  }

  /// Format the responded_at date for display
  func formattedResponseDate(locale: Locale) -> String? {
    guard let respondedAt else {
      return nil
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    guard let date = formatter.date(from: respondedAt) else {
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: respondedAt) else {
        return respondedAt
      }
      return formatDate(date, locale: locale)
    }

    return formatDate(date, locale: locale)
  }

  private func formatDate(_ date: Date, locale: Locale) -> String {
    let displayFormatter = DateFormatter()
    displayFormatter.dateStyle = .medium
    displayFormatter.timeStyle = .none
    displayFormatter.locale = locale
    return displayFormatter.string(from: date)
  }
}
