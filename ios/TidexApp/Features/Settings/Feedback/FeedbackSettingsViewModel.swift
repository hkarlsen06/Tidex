import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "FeedbackSettingsViewModel")

/// Maximum feedback message length
private let maxFeedbackLength = 2000

// MARK: - Models

/// A feedback item from the database
struct FeedbackItem: Codable, Identifiable {
  let id: String
  let userId: String
  let message: String
  let userEmail: String
  let createdAt: String
  let response: String?
  let respondedAt: String?
  let respondedBy: String?

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case message
    case userEmail = "user_email"
    case createdAt = "created_at"
    case response
    case respondedAt = "responded_at"
    case respondedBy = "responded_by"
  }
}

/// Data for inserting new feedback
struct FeedbackInsert: Encodable {
  let userId: String
  let message: String
  let userEmail: String

  enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case message
    case userEmail = "user_email"
  }
}

// MARK: - View Model

/// ViewModel for feedback settings
@MainActor
final class FeedbackSettingsViewModel: ObservableObject {

  // MARK: - Published State

  /// The feedback message being composed
  @Published var message: String = ""

  /// Loading state for initial data fetch
  @Published var isLoading: Bool = false

  /// Loading state for submitting feedback
  @Published var isSubmitting: Bool = false

  /// Error message to display
  @Published var errorMessage: String?

  /// Whether feedback was successfully submitted
  @Published var showSuccess: Bool = false

  /// History of user's feedback
  @Published var feedbackHistory: [FeedbackItem] = []

  /// Currently expanded feedback item ID
  @Published var expandedItemId: String?

  // MARK: - Computed Properties

  /// Current character count
  var characterCount: Int {
    message.count
  }

  /// Whether the message exceeds the max length
  var isOverLimit: Bool {
    message.count > maxFeedbackLength
  }

  /// Whether the submit button should be enabled
  var canSubmit: Bool {
    !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isOverLimit
      && !isSubmitting
  }

  /// Formatted character count string
  var characterCountText: String {
    "\(characterCount) / \(maxFeedbackLength)"
  }

  // MARK: - Private Properties

  private var userId: String?
  private var userEmail: String?

  // MARK: - Initialization

  init() {}

  // MARK: - Public Methods

  /// Load initial data - user info and feedback history
  func loadData() async {
    isLoading = true
    errorMessage = nil

    do {
      // Get current user session
      let session = try await AuthSessionManager.shared.getSession()
      userId = session.normalizedUserId
      userEmail = session.user.email ?? ""

      // Fetch feedback history
      await fetchFeedbackHistory()

    } catch {
      logger.error("Failed to get user session: \(error.localizedDescription)")
      errorMessage = "Not authenticated"
    }

    isLoading = false
  }

  /// Submit new feedback
  func submitFeedback() async {
    guard let userId = userId, let userEmail = userEmail else {
      errorMessage = "Not authenticated"
      return
    }

    let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedMessage.isEmpty else {
      errorMessage = "Please enter your feedback"
      return
    }

    guard trimmedMessage.count <= maxFeedbackLength else {
      errorMessage = "Feedback must be \(maxFeedbackLength) characters or less"
      return
    }

    isSubmitting = true
    errorMessage = nil

    do {
      let feedback = FeedbackInsert(
        userId: userId,
        message: trimmedMessage,
        userEmail: userEmail
      )

      try await supabase
        .from("feedback")
        .insert(feedback)
        .execute()

      logger.info("Feedback submitted successfully")

      // Clear the form and show success
      message = ""
      showSuccess = true

      // Refresh history
      await fetchFeedbackHistory()

    } catch {
      logger.error("Failed to submit feedback: \(error.localizedDescription)")
      errorMessage = "Failed to send feedback. Please try again."
    }

    isSubmitting = false
  }

  /// Clear error message
  func clearError() {
    errorMessage = nil
  }

  /// Reset success state to show form again
  func resetSuccess() {
    showSuccess = false
  }

  /// Toggle expanded state for a feedback item
  func toggleExpanded(_ itemId: String) {
    if expandedItemId == itemId {
      expandedItemId = nil
    } else {
      expandedItemId = itemId
    }
  }

  // MARK: - Private Methods

  /// Fetch user's feedback history
  private func fetchFeedbackHistory() async {
    guard let userId else { return }

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
      logger.info("Fetched \(items.count) feedback items")

    } catch {
      logger.error("Failed to fetch feedback history: \(error.localizedDescription)")
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
    guard let respondedAt = respondedAt else { return nil }

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
