import Foundation

// MARK: - Event Row

/// Private calendar-style event from the `events` table.
struct EventRow: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String?
  let start_date: String
  let end_date: String
  let is_all_day: Bool
  let start_time: String?
  let end_time: String?
  let note: String
  let created_at: String?
  let updated_at: Date?

  init(
    id: String,
    user_id: String?,
    start_date: String,
    end_date: String,
    is_all_day: Bool,
    start_time: String?,
    end_time: String?,
    note: String,
    created_at: String? = nil,
    updated_at: Date? = nil
  ) {
    self.id = id
    self.user_id = user_id
    self.start_date = start_date
    self.end_date = end_date
    self.is_all_day = is_all_day
    self.start_time = start_time
    self.end_time = end_time
    self.note = note
    self.created_at = created_at
    self.updated_at = updated_at
  }

  var trimmedNote: String {
    note.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
