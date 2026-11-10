import Foundation

// MARK: - Shared RPC Models

enum SharingRPCMode: Sendable {
  case visible
  case hidden
}

struct PauseWindow: Codable, Equatable, Hashable, Sendable {
  let start: String
  let end: String
}

struct CustomPauseWindows: Codable, Equatable, Hashable, Sendable {
  let windows: [PauseWindow]
}

typealias DateSpecificPauseWindows = [String: CustomPauseWindows]

enum BreakAuditSource: String, Codable, Equatable, Sendable {
  case none
  case automaticBreak = "automatic_break"
  case customPauseWindows = "custom_pause_windows"
}

struct PauseClipPeriod: Equatable, Sendable {
  let fromMin: Double
  let toMin: Double
  let baseRate: Double
  let supplementRate: Double
}

struct PauseWindowClipResult: Equatable, Sendable {
  let periods: [PauseClipPeriod]
  let deductedHours: Double
  let appliedPauseWindows: [PauseWindow]?
}

enum PauseWindowSupport {
  static func normalize(_ value: CustomPauseWindows?) -> CustomPauseWindows? {
    guard let value else { return nil }

    let normalized = value.windows.compactMap { window -> PauseWindow? in
      guard let start = normalizedTime(window.start), let end = normalizedTime(window.end) else {
        return nil
      }
      guard start != end else { return nil }
      return PauseWindow(start: start, end: end)
    }

    guard !normalized.isEmpty else { return nil }

    let uniqueSorted = Array(Set(normalized)).sorted {
      if $0.start == $1.start {
        return $0.end < $1.end
      }
      return $0.start < $1.start
    }

    return CustomPauseWindows(windows: uniqueSorted)
  }

  static func normalize(_ value: DateSpecificPauseWindows?) -> DateSpecificPauseWindows? {
    guard let value else { return nil }

    let normalized = value.reduce(into: DateSpecificPauseWindows()) { result, entry in
      guard isValidISODate(entry.key) else { return }
      guard let windows = normalize(entry.value) else { return }
      result[entry.key] = windows
    }

    return normalized.isEmpty ? nil : normalized
  }

  static func apply(
    customPauseWindows: CustomPauseWindows,
    startTime: String,
    endTime: String,
    periods: [PauseClipPeriod]
  ) -> PauseWindowClipResult {
    guard let normalized = normalize(customPauseWindows), !periods.isEmpty else {
      return PauseWindowClipResult(periods: periods, deductedHours: 0, appliedPauseWindows: nil)
    }

    let pauseIntervals = clippedIntervals(
      windows: normalized.windows,
      shiftStartTime: startTime,
      shiftEndTime: endTime
    )

    guard !pauseIntervals.isEmpty else {
      return PauseWindowClipResult(periods: periods, deductedHours: 0, appliedPauseWindows: nil)
    }

    var clipped: [PauseClipPeriod] = []

    for period in periods {
      var cursor = period.fromMin

      for interval in pauseIntervals {
        if interval.end <= cursor || interval.start >= period.toMin {
          continue
        }

        let overlapStart = max(cursor, interval.start)
        let overlapEnd = min(period.toMin, interval.end)

        if overlapStart > cursor {
          clipped.append(
            PauseClipPeriod(
              fromMin: cursor,
              toMin: overlapStart,
              baseRate: period.baseRate,
              supplementRate: period.supplementRate
            ))
        }

        cursor = max(cursor, overlapEnd)
        if cursor >= period.toMin {
          break
        }
      }

      if cursor < period.toMin {
        clipped.append(
          PauseClipPeriod(
            fromMin: cursor,
            toMin: period.toMin,
            baseRate: period.baseRate,
            supplementRate: period.supplementRate
          ))
      }
    }

    let deductedMinutes = pauseIntervals.reduce(0.0) { $0 + ($1.end - $1.start) }
    let appliedWindows = pauseIntervals.map { interval in
      PauseWindow(
        start: minutesToTimeString(interval.start),
        end: minutesToTimeString(interval.end)
      )
    }

    return PauseWindowClipResult(
      periods: clipped.filter { $0.toMin > $0.fromMin },
      deductedHours: deductedMinutes / 60.0,
      appliedPauseWindows: appliedWindows.isEmpty ? nil : appliedWindows
    )
  }

  static func isWithinShift(
    _ window: PauseWindow,
    shiftStartTime: String,
    shiftEndTime: String
  ) -> Bool {
    guard let normalized = normalize(CustomPauseWindows(windows: [window]))?.windows.first else {
      return false
    }

    let shiftStart = Double(timeToMinutes(shiftStartTime))
    var shiftEnd = Double(timeToMinutes(shiftEndTime))
    if shiftEnd <= shiftStart {
      shiftEnd += 24 * 60
    }

    let windowStart = Double(timeToMinutes(normalized.start))
    var windowEnd = Double(timeToMinutes(normalized.end))
    if windowEnd <= windowStart {
      windowEnd += 24 * 60
    }

    for base in [0.0, 24.0 * 60.0] {
      let start = windowStart + base
      let end = windowEnd + base
      if start >= shiftStart, end <= shiftEnd {
        return true
      }
    }

    return false
  }

  private static func clippedIntervals(
    windows: [PauseWindow],
    shiftStartTime: String,
    shiftEndTime: String
  ) -> [(start: Double, end: Double)] {
    let shiftStart = Double(timeToMinutes(shiftStartTime))
    var shiftEnd = Double(timeToMinutes(shiftEndTime))
    if shiftEnd <= shiftStart {
      shiftEnd += 24 * 60
    }

    var intervals: [(start: Double, end: Double)] = []

    for window in windows {
      let windowStart = Double(timeToMinutes(window.start))
      var windowEnd = Double(timeToMinutes(window.end))
      if windowEnd <= windowStart {
        windowEnd += 24 * 60
      }

      for base in [0.0, 24.0 * 60.0] {
        let start = windowStart + base
        let end = windowEnd + base
        let clippedStart = max(start, shiftStart)
        let clippedEnd = min(end, shiftEnd)

        if clippedEnd > clippedStart {
          intervals.append((start: clippedStart, end: clippedEnd))
        }
      }
    }

    let sorted = intervals.sorted {
      if $0.start == $1.start {
        return $0.end < $1.end
      }
      return $0.start < $1.start
    }

    guard var current = sorted.first else { return [] }
    var merged: [(start: Double, end: Double)] = []

    for interval in sorted.dropFirst() {
      if interval.start <= current.end {
        current.end = max(current.end, interval.end)
      } else {
        merged.append(current)
        current = interval
      }
    }

    merged.append(current)
    return merged
  }

  private static func normalizedTime(_ value: String) -> String? {
    let parts = value.split(separator: ":")
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      minutes >= 0,
      minutes < 60,
      hours >= 0,
      hours <= 24
    else {
      return nil
    }

    guard hours < 24 || minutes == 0 else { return nil }
    return String(format: "%02d:%02d", hours, minutes)
  }

  private static func timeToMinutes(_ hhmm: String) -> Int {
    let normalized = normalizedTime(hhmm) ?? "00:00"
    let parts = normalized.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return 0 }
    return (parts[0] * 60) + parts[1]
  }

  private static func minutesToTimeString(_ minutes: Double) -> String {
    let rounded = Int(minutes.rounded())
    let normalized = ((rounded % (24 * 60)) + (24 * 60)) % (24 * 60)
    if rounded > 0, normalized == 0 {
      return "24:00"
    }
    let hours = normalized / 60
    let mins = normalized % 60
    return String(format: "%02d:%02d", hours, mins)
  }

  private static func isValidISODate(_ value: String) -> Bool {
    let parts = value.split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else {
      return false
    }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    return components.date != nil
  }
}

struct SharingRPCSharerRow: Decodable, Sendable {
  let id: String
  let email: String?
  let phone: String?
  let username: String?
  let firstName: String?
  let profilePictureUrl: String?
  let oauthAvatarUrl: String?
  let sharedAt: String
  let showEarnings: Bool
  let hidden: Bool
  let hasSharedCalendarContent: Bool
  let latestSharedShiftDate: String?
  let hasRecurringSharedShifts: Bool

  private enum CodingKeys: String, CodingKey {
    case id
    case email
    case phone
    case username
    case firstName = "first_name"
    case profilePictureUrl = "profile_picture_url"
    case oauthAvatarUrl = "oauth_avatar_url"
    case sharedAt = "shared_at"
    case showEarnings = "show_earnings"
    case hidden
    case hasSharedCalendarContent = "has_shared_calendar_content"
    case latestSharedShiftDate = "latest_shared_shift_date"
    case hasRecurringSharedShifts = "has_recurring_shared_shifts"
    case blocked
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    phone = try container.decodeIfPresent(String.self, forKey: .phone)
    username = try container.decodeIfPresent(String.self, forKey: .username)
    firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
    profilePictureUrl = try container.decodeIfPresent(String.self, forKey: .profilePictureUrl)
    oauthAvatarUrl = try container.decodeIfPresent(String.self, forKey: .oauthAvatarUrl)
    sharedAt = try container.decode(String.self, forKey: .sharedAt)
    showEarnings = try container.decode(Bool.self, forKey: .showEarnings)
    hidden =
      try container.decodeIfPresent(Bool.self, forKey: .hidden)
      ?? container.decodeIfPresent(Bool.self, forKey: .blocked)
      ?? false
    hasSharedCalendarContent =
      try container.decodeIfPresent(Bool.self, forKey: .hasSharedCalendarContent)
      ?? false
    latestSharedShiftDate = try container.decodeIfPresent(
      String.self, forKey: .latestSharedShiftDate)
    hasRecurringSharedShifts =
      try container.decodeIfPresent(Bool.self, forKey: .hasRecurringSharedShifts)
      ?? false
  }
}

struct SharingRPCUserSettings: Codable, Sendable {
  let userId: String?
  let monthlyGoal: Double?
  let monthlyGoalsByMonth: [String: Int]?
  let defaultShiftsView: String?
  let profilePictureUrl: String?
  let payrollDay: Int?
  let theme: String?
  let calendarAnimationStyle: String?
  let halfTaxMonth: Int?
  let currency: String?

  var effectivePayrollDay: Int {
    payrollDay ?? 1
  }

  private enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case monthlyGoal = "monthly_goal"
    case monthlyGoalsByMonth = "monthly_goals_by_month"
    case defaultShiftsView = "default_shifts_view"
    case profilePictureUrl = "profile_picture_url"
    case payrollDay = "payroll_day"
    case theme
    case calendarAnimationStyle = "calendar_animation_style"
    case halfTaxMonth = "half_tax_month"
    case currency
  }
}

struct SharingRPCJobRow: Codable, Equatable, Sendable {
  let id: String
  let userId: String
  let name: String
  let color: String?
  let currency: String?
  let isDefault: Bool
  let sortOrder: Int?
  let payrollDay: Int?
  let payPeriod: PayPeriod?
  let halfTaxMonth: Int?
  let monthlyGoal: Double?
  let archivedAt: String?
  let deletedAt: String?
  let createdAt: String?
  let updatedAt: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case name
    case color
    case currency
    case isDefault = "is_default"
    case sortOrder = "sort_order"
    case payrollDay = "payroll_day"
    case payPeriod = "pay_period"
    case halfTaxMonth = "half_tax_month"
    case monthlyGoal = "monthly_goal"
    case archivedAt = "archived_at"
    case deletedAt = "deleted_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

struct SharingRPCSupplementRule: Codable, Equatable, Sendable {
  var stackingGroup: String?
  var dates: [String]?
  var excludedDates: [String]?
  var shiftStartDates: [String]?
  var excludedShiftStartDates: [String]?
  var shiftStartBefore: String?
  var minimumRate: Double?
  var percentageBaseRate: Double?
  let days: [Int]
  let from: String
  let to: String
  let rate: Double?
  let percent: Double?
}

struct SharingRPCCustomSupplementRule: Codable, Equatable, Sendable {
  var stackingGroup: String?
  var dates: [String]?
  var excludedDates: [String]?
  var shiftStartDates: [String]?
  var excludedShiftStartDates: [String]?
  var shiftStartBefore: String?
  var minimumRate: Double?
  var percentageBaseRate: Double?
  let from: String
  let to: String
  let rate: Double?
  let percent: Double?
  let isCustom: Bool?

  private enum CodingKeys: String, CodingKey {
    case from
    case to
    case rate
    case percent
    case isCustom = "is_custom"
    case stackingGroup, dates, excludedDates, shiftStartDates, excludedShiftStartDates
    case minimumRate, percentageBaseRate, shiftStartBefore
  }
}

struct SharingRPCCustomSupplements: Codable, Equatable, Sendable {
  let rules: [SharingRPCCustomSupplementRule]
}

struct SharingRPCSupplementRulesSnapshot: Codable, Equatable, Sendable {
  let rules: [SharingRPCSupplementRule]
}

enum SharingRPCEndCondition: Codable, Equatable, Sendable {
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
      self = .months(value: try container.decode(Int.self, forKey: .value))

    case "years":
      self = .years(value: try container.decode(Int.self, forKey: .value))

    case "end_date":
      if let date = try? container.decode(String.self, forKey: .date) {
        self = .endDate(date: date)
      } else if let value = try? container.decode(String.self, forKey: .value) {
        self = .endDate(date: value)
      } else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "end_date requires either 'date' or 'value' key"
          ))
      }

    default:
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unknown end condition type: \(type)"
        ))
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

struct SharingRPCShiftRow: Codable, Sendable {
  let id: String
  let userId: String
  let jobId: String?
  let shiftDate: String
  let startTime: String
  let endTime: String
  let customPauseWindows: CustomPauseWindows?
  let customSupplements: SharingRPCCustomSupplements?
  let recurringId: String?
  let recurringAnchorWeekday: Int?

  private enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case jobId = "job_id"
    case shiftDate = "shift_date"
    case startTime = "start_time"
    case endTime = "end_time"
    case customPauseWindows = "custom_pause_windows"
    case customSupplements = "custom_supplements"
    case recurringId = "recurring_id"
    case recurringAnchorWeekday = "recurring_anchor_weekday"
  }
}

struct SharingRPCRecurringShiftRow: Codable, Sendable {
  let id: String
  let userId: String
  let jobId: String?
  let startTime: String
  let endTime: String
  let repeatIntervalWeeks: Int
  let selectedDays: [String: String]
  let endCondition: SharingRPCEndCondition?
  let exclusions: [String]?
  let dateSpecificPauseWindows: DateSpecificPauseWindows?
  let dateSpecificSupplements: [String: SharingRPCCustomSupplements]?

  var cleanStartTime: String {
    Self.cleanTime(startTime)
  }

  var cleanEndTime: String {
    Self.cleanTime(endTime)
  }

  private static func cleanTime(_ time: String) -> String {
    var cleaned = time

    if let plusIndex = cleaned.firstIndex(of: "+") {
      cleaned = String(cleaned[..<plusIndex])
    }

    if let minusIndex = cleaned.lastIndex(of: "-"),
      cleaned.distance(from: cleaned.startIndex, to: minusIndex) > 2
    {
      cleaned = String(cleaned[..<minusIndex])
    }

    return String(cleaned.prefix(5))
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case jobId = "job_id"
    case startTime = "start_time"
    case endTime = "end_time"
    case repeatIntervalWeeks = "repeat_interval_weeks"
    case selectedDays = "selected_days"
    case endCondition = "end_condition"
    case exclusions
    case dateSpecificPauseWindows = "date_specific_pause_windows"
    case dateSpecificSupplements = "date_specific_supplements"
  }
}

struct SharingRPCOvertimeRule: Codable, Equatable, Sendable {
  let days: [Int]
  let appliesOnHolidays: Bool
  let from: String
  let to: String
  let percent: Double
  var dates: [String]?
  var excludedDates: [String]?
}

struct SharingRPCOvertimeConfig: Codable, Equatable, Sendable {
  let enabled: Bool
  let weeklyThresholdHours: Double
  let rules: [SharingRPCOvertimeRule]
  var retainSupplements: Bool?
  var premiumBaseMultiplier: Double?
  var baseRate: Double?
  var retainedSupplements: [SharingRPCSupplementRule]?

  static let disabled = SharingRPCOvertimeConfig(
    enabled: false,
    weeklyThresholdHours: 40,
    rules: []
  )
}

struct SharingRPCWageSnapshot: Codable, Sendable {
  let id: String
  let userId: String
  let jobId: String?
  let fromDate: String?
  let hourlyWage: Double
  let wageLevel: Int?
  let tariffTypeId: String?
  let supplements: SharingRPCSupplementRulesSnapshot
  let overtime: SharingRPCOvertimeConfig?
  let taxEnabled: Bool?
  let taxPercentage: Double?
  let breakEnabled: Bool?
  let breakMethod: String?
  let breakThresholdHours: Double?
  let breakDeductionMinutes: Int?

  var effectiveTaxEnabled: Bool {
    taxEnabled ?? false
  }

  var effectiveTaxPercentage: Double {
    taxPercentage ?? 0
  }

  var effectiveOvertime: SharingRPCOvertimeConfig {
    overtime ?? .disabled
  }

  var effectiveBreakEnabled: Bool {
    breakEnabled ?? true
  }

  var effectiveBreakThresholdHours: Double {
    breakThresholdHours ?? 5.5
  }

  var effectiveBreakDeductionMinutes: Int {
    breakDeductionMinutes ?? 30
  }

  var effectiveBreakMethod: SharingRPCBreakMethod {
    guard let breakMethod else { return .proportional }
    return SharingRPCBreakMethod(rawValue: breakMethod) ?? .proportional
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case jobId = "job_id"
    case fromDate = "from_date"
    case hourlyWage = "hourly_wage"
    case wageLevel = "wage_level"
    case tariffTypeId = "tariff_type_id"
    case supplements
    case overtime
    case taxEnabled = "tax_enabled"
    case taxPercentage = "tax_percentage"
    case breakEnabled = "break_enabled"
    case breakMethod = "break_method"
    case breakThresholdHours = "break_threshold_hours"
    case breakDeductionMinutes = "break_deduction_minutes"
  }
}

struct SharingRPCPreviewPayloadRow: Codable, Sendable {
  let sharerId: String
  let ownerTimeZone: String?
  let showEarnings: Bool
  let settings: SharingRPCUserSettings
  let shifts: [SharingRPCShiftRow]
  let recurringShifts: [SharingRPCRecurringShiftRow]
  let snapshots: [SharingRPCWageSnapshot]
  let jobs: [SharingRPCJobRow]

  var payloadInput: SharingRPCPayloadInput {
    SharingRPCPayloadInput(
      ownerId: sharerId,
      showEarnings: showEarnings,
      settings: settings,
      shifts: shifts,
      recurringShifts: recurringShifts,
      snapshots: snapshots,
      jobs: jobs
    )
  }

  private enum CodingKeys: String, CodingKey {
    case sharerId = "sharer_id"
    case ownerTimeZone = "owner_time_zone"
    case showEarnings = "show_earnings"
    case settings
    case shifts
    case recurringShifts = "recurring_shifts"
    case snapshots
    case jobs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sharerId = try container.decode(String.self, forKey: .sharerId)
    ownerTimeZone = try container.decodeIfPresent(String.self, forKey: .ownerTimeZone)
    showEarnings = try container.decode(Bool.self, forKey: .showEarnings)
    settings =
      try container.decodeIfPresent(SharingRPCUserSettings.self, forKey: .settings)
      ?? SharingRPCUserSettings(
        userId: sharerId,
        monthlyGoal: nil,
        monthlyGoalsByMonth: nil,
        defaultShiftsView: nil,
        profilePictureUrl: nil,
        payrollDay: nil,
        theme: nil,
        calendarAnimationStyle: nil,
        halfTaxMonth: nil,
        currency: nil
      )
    shifts = try container.decodeIfPresent([SharingRPCShiftRow].self, forKey: .shifts) ?? []
    recurringShifts =
      try container.decodeIfPresent([SharingRPCRecurringShiftRow].self, forKey: .recurringShifts)
      ?? []
    snapshots =
      try container.decodeIfPresent([SharingRPCWageSnapshot].self, forKey: .snapshots)
      ?? []
    jobs = try container.decodeIfPresent([SharingRPCJobRow].self, forKey: .jobs) ?? []
  }
}

struct SharingRPCMonthPayloadRow: Codable, Sendable {
  let ownerId: String
  let ownerTimeZone: String?
  let showEarnings: Bool
  let settings: SharingRPCUserSettings
  let shifts: [SharingRPCShiftRow]
  let recurringShifts: [SharingRPCRecurringShiftRow]
  let snapshots: [SharingRPCWageSnapshot]
  let jobs: [SharingRPCJobRow]

  var payloadInput: SharingRPCPayloadInput {
    SharingRPCPayloadInput(
      ownerId: ownerId,
      showEarnings: showEarnings,
      settings: settings,
      shifts: shifts,
      recurringShifts: recurringShifts,
      snapshots: snapshots,
      jobs: jobs
    )
  }

  private enum CodingKeys: String, CodingKey {
    case ownerId = "owner_id"
    case ownerTimeZone = "owner_time_zone"
    case showEarnings = "show_earnings"
    case settings
    case shifts
    case recurringShifts = "recurring_shifts"
    case snapshots
    case jobs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ownerId = try container.decode(String.self, forKey: .ownerId)
    ownerTimeZone = try container.decodeIfPresent(String.self, forKey: .ownerTimeZone)
    showEarnings = try container.decode(Bool.self, forKey: .showEarnings)
    settings =
      try container.decodeIfPresent(SharingRPCUserSettings.self, forKey: .settings)
      ?? SharingRPCUserSettings(
        userId: ownerId,
        monthlyGoal: nil,
        monthlyGoalsByMonth: nil,
        defaultShiftsView: nil,
        profilePictureUrl: nil,
        payrollDay: nil,
        theme: nil,
        calendarAnimationStyle: nil,
        halfTaxMonth: nil,
        currency: nil
      )
    shifts = try container.decodeIfPresent([SharingRPCShiftRow].self, forKey: .shifts) ?? []
    recurringShifts =
      try container.decodeIfPresent([SharingRPCRecurringShiftRow].self, forKey: .recurringShifts)
      ?? []
    snapshots =
      try container.decodeIfPresent([SharingRPCWageSnapshot].self, forKey: .snapshots)
      ?? []
    jobs = try container.decodeIfPresent([SharingRPCJobRow].self, forKey: .jobs) ?? []
  }
}

struct SharingRPCPayloadInput: Sendable {
  let ownerId: String
  let showEarnings: Bool
  let settings: SharingRPCUserSettings
  let shifts: [SharingRPCShiftRow]
  let recurringShifts: [SharingRPCRecurringShiftRow]
  let snapshots: [SharingRPCWageSnapshot]
  let jobs: [SharingRPCJobRow]
}

struct SharingRPCPayoutTaxSettings: Equatable, Sendable {
  let enabled: Bool
  let percentage: Double
}
