// MARK: - Selected Days

/// Anchor dates by weekday key
/// Key is weekday (0-6 where 0=Sunday), value is ISO date string
typealias SelectedDays = [String: String]

// MARK: - End Condition

/// End condition for recurring shifts
/// Handles two JSON formats:
/// - {"type": "end_date", "value": "2025-12-31"} - older format with "value" key
/// - {"type": "end_date", "date": "2026-08-03", "end_time": "23:59"} - newer format with "date" key
enum EndCondition: Codable, Equatable {
  case months(value: Int)
  case years(value: Int)
  case endDate(date: String)

  private enum CodingKeys: String, CodingKey {
    case type
    case value
    case date
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "months":
      let value = try container.decode(Int.self, forKey: .value)
      self = .months(value: value)
    case "years":
      let value = try container.decode(Int.self, forKey: .value)
      self = .years(value: value)
    case "end_date":
      // Handle both formats: "date" key (newer) or "value" key (older)
      if let date = try? container.decode(String.self, forKey: .date) {
        self = .endDate(date: date)
      } else if let value = try? container.decode(String.self, forKey: .value) {
        self = .endDate(date: value)
      } else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "end_date requires either 'date' or 'value' key")
        )
      }
    default:
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath, debugDescription: "Unknown end condition type: \(type)")
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .months(let value):
      try container.encode("months", forKey: .type)
      try container.encode(value, forKey: .value)
    case .years(let value):
      try container.encode("years", forKey: .type)
      try container.encode(value, forKey: .value)
    case .endDate(let date):
      try container.encode("end_date", forKey: .type)
      try container.encode(date, forKey: .date)
    }
  }
}

// MARK: - Recurring Shift Row

/// Recurring shift from the recurring_shifts table
struct RecurringShiftRow: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String
  /// Job that owns this recurring pattern (nullable during rollout compatibility)
  var job_id: String? = nil
  /// Start time (HH:mm or HH:mm:ss+TZ from timetz)
  let start_time: String
  /// End time (HH:mm or HH:mm:ss+TZ from timetz)
  let end_time: String
  /// Repetition interval: 0 = every week, 1 = every 2 weeks, etc.
  let repeat_interval_weeks: Int
  /// Anchor dates by weekday (0-6)
  let selected_days: SelectedDays
  /// Optional end condition
  let end_condition: EndCondition?
  /// Excluded dates (ISO format)
  let exclusions: [String]?
  /// Custom pause windows for specific dates
  let date_specific_pause_windows: DateSpecificPauseWindows?
  /// Custom supplements for specific dates
  let date_specific_supplements: [String: CustomSupplementsData]?
  /// Private notes for specific virtual occurrence dates
  let date_specific_notes: [String: String]?

  /// Effective exclusions (empty array if nil)
  var effectiveExclusions: [String] {
    exclusions ?? []
  }

  /// Clean start time (removes timezone suffix from timetz)
  var cleanStartTime: String {
    cleanTime(start_time)
  }

  /// Clean end time (removes timezone suffix from timetz)
  var cleanEndTime: String {
    cleanTime(end_time)
  }

  func makeVirtualShift(
    date: String,
    weekday: Int,
    id: String? = nil,
    userId: String? = nil
  ) -> ShiftRow {
    ShiftRow(
      id: id ?? "virtual-\(self.id)-\(date)",
      user_id: userId ?? user_id,
      job_id: job_id,
      shift_date: date,
      start_time: cleanStartTime,
      end_time: cleanEndTime,
      note: date_specific_notes?[date],
      custom_pause_windows: date_specific_pause_windows?[date],
      custom_supplements: date_specific_supplements?[date],
      created_at: nil,
      updated_at: nil,
      recurring_id: self.id,
      recurring_anchor_weekday: weekday
    )
  }

  /// Remove timezone suffix from timetz (e.g., "08:00:00+01:00" -> "08:00")
  private func cleanTime(_ time: String) -> String {
    var cleaned = time

    // Remove +TZ suffix
    if let plusIndex = cleaned.firstIndex(of: "+") {
      cleaned = String(cleaned[..<plusIndex])
    }

    // Remove -TZ suffix (but not time part)
    if let minusIndex = cleaned.lastIndex(of: "-"),
      cleaned.distance(from: cleaned.startIndex, to: minusIndex) > 2
    {
      cleaned = String(cleaned[..<minusIndex])
    }

    // Keep only HH:mm
    return String(cleaned.prefix(5))
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case user_id
    case job_id
    case start_time
    case end_time
    case repeat_interval_weeks
    case selected_days
    case end_condition
    case exclusions
    case date_specific_pause_windows
    case date_specific_supplements
    case date_specific_notes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    user_id = try container.decode(String.self, forKey: .user_id)
    job_id = try container.decodeIfPresent(String.self, forKey: .job_id)
    start_time = try container.decode(String.self, forKey: .start_time)
    end_time = try container.decode(String.self, forKey: .end_time)
    repeat_interval_weeks = try container.decode(Int.self, forKey: .repeat_interval_weeks)
    selected_days = try container.decode(SelectedDays.self, forKey: .selected_days)
    end_condition = try container.decodeIfPresent(EndCondition.self, forKey: .end_condition)
    exclusions = try container.decodeIfPresent([String].self, forKey: .exclusions)
    date_specific_pause_windows = PauseWindowSupport.normalize(
      try container.decodeIfPresent(
        DateSpecificPauseWindows.self, forKey: .date_specific_pause_windows)
    )
    date_specific_supplements = try container.decodeIfPresent(
      [String: CustomSupplementsData].self,
      forKey: .date_specific_supplements
    )
    date_specific_notes = ShiftNoteSupport.normalizeDateSpecificNotes(
      try container.decodeIfPresent([String: String].self, forKey: .date_specific_notes)
    )
  }

  init(
    id: String,
    user_id: String,
    job_id: String? = nil,
    start_time: String,
    end_time: String,
    repeat_interval_weeks: Int,
    selected_days: SelectedDays,
    end_condition: EndCondition?,
    exclusions: [String]?,
    date_specific_pause_windows: DateSpecificPauseWindows? = nil,
    date_specific_supplements: [String: CustomSupplementsData]? = nil,
    date_specific_notes: [String: String]? = nil
  ) {
    self.id = id
    self.user_id = user_id
    self.job_id = job_id
    self.start_time = start_time
    self.end_time = end_time
    self.repeat_interval_weeks = repeat_interval_weeks
    self.selected_days = selected_days
    self.end_condition = end_condition
    self.exclusions = exclusions
    self.date_specific_pause_windows = PauseWindowSupport.normalize(date_specific_pause_windows)
    self.date_specific_supplements = date_specific_supplements
    self.date_specific_notes = ShiftNoteSupport.normalizeDateSpecificNotes(date_specific_notes)
  }
}

// MARK: - Virtual Shift

/// Virtual shift occurrence generated from a recurring pattern
struct RecurringVirtualShift: Equatable {
  /// Date of the virtual shift (YYYY-MM-DD)
  let date: String
  /// Weekday (0-6 where 0=Sunday)
  let weekday: Int
}
