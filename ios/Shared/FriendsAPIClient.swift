// swiftlint:disable file_length function_body_length cyclomatic_complexity
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable anonymous_argument_in_multiline_closure conditional_returns_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable discouraged_none_name discouraged_optional_boolean discouraged_optional_collection
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_enum_raw_value explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order function_parameter_count identifier_name
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable multiline_arguments_brackets no_magic_numbers pattern_matching_keywords
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_enum_cases strict_fileprivate switch_case_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_body_length type_contents_order
import Foundation

#if canImport(UIKit)
  import UIKit
#endif

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
  let days: [Int]
  let from: String
  let to: String
  let rate: Double?
  let percent: Double?
}

struct SharingRPCCustomSupplementRule: Codable, Equatable, Sendable {
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
}

struct SharingRPCOvertimeConfig: Codable, Equatable, Sendable {
  let enabled: Bool
  let weeklyThresholdHours: Double
  let rules: [SharingRPCOvertimeRule]

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

  fileprivate var effectiveBreakMethod: SharingRPCBreakMethod {
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

// MARK: - Shared Compute Models

struct SharingComputedShiftComputed: Equatable, Sendable {
  let durationHours: Double
  let paidHours: Double
  let basePay: Double
  let supplementPay: Double
  let gross: Double
  let wagePeriods: [SharingRPCWagePeriod]
  let originalWagePeriods: [SharingRPCWagePeriod]
  let breakAudit: SharingRPCBreakAudit
  var overtimeApplied: Bool = false
  var overtimeMinutes: Double = 0
}

struct SharingComputedShift: Identifiable, Equatable, Sendable {
  let id: String
  let userId: String
  let jobId: String?
  let jobName: String?
  let jobColor: String?
  let shiftDate: String
  let startTime: String
  let endTime: String
  let customPauseWindows: CustomPauseWindows?
  let customSupplements: SharingRPCCustomSupplements?
  let recurringId: String?
  let recurringAnchorWeekday: Int?
  let computed: SharingComputedShiftComputed
  let taxEnabled: Bool
  let taxPercentage: Double
}

enum SharingPreviewStatus: String, Codable, Sendable {
  case active
  case upcoming
  case past
}

struct SharingComputedPreview: Sendable {
  let sharerId: String
  let shift: SharingComputedShift?
  let status: SharingPreviewStatus?
  let showEarnings: Bool
}

enum SharingRPCBreakMethod: String, Codable, Equatable, Sendable {
  case proportional = "proportional"
  case baseOnly = "base_only"
  case endOfShift = "end_of_shift"
  case none = "none"
}

struct SharingRPCWagePeriod: Equatable, Sendable {
  let fromMin: Double
  let toMin: Double
  let baseRate: Double
  let supplementRate: Double
  var isOvertime: Bool?

  var durationMinutes: Double { toMin - fromMin }
  var durationHours: Double { durationMinutes / 60.0 }
}

struct SharingRPCBreakAudit: Equatable, Sendable {
  let method: SharingRPCBreakMethod
  let thresholdHours: Double
  let deductedHours: Double
  let source: BreakAuditSource
  let appliedPauseWindows: [PauseWindow]?
  let notes: [String]
}

private struct SharingRPCBreakDeductionResult: Equatable, Sendable {
  let periods: [SharingRPCWagePeriod]
  let audit: SharingRPCBreakAudit
}

private struct SharingRecurringVirtualShift: Equatable, Sendable {
  let date: String
  let weekday: Int
}

private struct SharingPayrollContext {
  let fallbackPayrollDay: Int
  let fallbackHalfTaxMonth: Int?
  let jobsById: [String: SharingRPCJobRow]
  let defaultJobId: String?
  let snapshotsByJobId: [String?: [SharingRPCWageSnapshot]]
  let legacyNilJobSnapshots: [SharingRPCWageSnapshot]
  let allSnapshots: [SharingRPCWageSnapshot]
}

// MARK: - Shared Compute Core (Foundation-only)

enum SharingComputeCore {
  private static let defaultBreakEnabled = true
  private static let defaultBreakThresholdHours = 5.5
  private static let defaultBreakDeductionMinutes = 30
  private static let fallbackBaseRate = 184.54

  private static let presetSupplementRules: [SharingRPCSupplementRule] = [
    SharingRPCSupplementRule(
      days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22, percent: nil),
    SharingRPCSupplementRule(
      days: [1, 2, 3, 4, 5], from: "21:00", to: "24:00", rate: 45, percent: nil),
    SharingRPCSupplementRule(days: [6], from: "13:00", to: "15:00", rate: 45, percent: nil),
    SharingRPCSupplementRule(days: [6], from: "15:00", to: "18:00", rate: 55, percent: nil),
    SharingRPCSupplementRule(days: [6], from: "18:00", to: "24:00", rate: 110, percent: nil),
    SharingRPCSupplementRule(days: [7], from: "00:00", to: "24:00", rate: 115, percent: nil),
  ]

  /// DateFormatter isn't safe to share across threads, so this caches one instance per
  /// thread (matching `FormatterCache`) instead of allocating one on every call in a loop.
  private static var isoDateFormatter: DateFormatter {
    let key = "tidex.sharing.isoDateFormatter"
    let dictionary = Thread.current.threadDictionary
    if let cached = dictionary[key] as? DateFormatter {
      return cached
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    dictionary[key] = formatter
    return formatter
  }

  static func isoDateString(_ date: Date) -> String {
    isoDateFormatter.string(from: date)
  }

  static func monthStart(year: Int, month: Int) -> String {
    String(format: "%04d-%02d-01", year, month)
  }

  static func monthEnd(year: Int, month: Int) -> String {
    let day = daysInMonth(year: year, month: month)
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  static func computeShiftsInRange(
    payload: SharingRPCPayloadInput,
    startDate: String,
    endDate: String,
    mode: SharingRPCMode
  ) -> [SharingComputedShift] {
    var computed: [SharingComputedShift] = []
    let context = makePayrollContext(
      settings: payload.settings,
      snapshots: payload.snapshots,
      jobs: payload.jobs
    )
    let calculationRange = expandedISOWeekRange(startDate: startDate, endDate: endDate)

    let regularShifts = payload.shifts.filter { shift in
      shift.shiftDate >= calculationRange.startDate && shift.shiftDate <= calculationRange.endDate
    }

    for shift in regularShifts {
      computed.append(
        computeShiftWithTax(
          shift: shift,
          context: context,
          mode: mode
        ))
    }

    let months = monthsInRange(
      startDate: calculationRange.startDate,
      endDate: calculationRange.endDate
    )
    var seenVirtualIds = Set<String>()

    for recurring in payload.recurringShifts {
      for (year, month) in months {
        let virtualShifts = generateVirtualShiftsForMonth(
          year: year,
          month: month,
          recurring: recurring
        )

        for virtual in virtualShifts {
          guard virtual.date >= calculationRange.startDate,
            virtual.date <= calculationRange.endDate
          else {
            continue
          }

          let virtualId = "virtual-\(recurring.id)-\(virtual.date)"
          guard !seenVirtualIds.contains(virtualId) else { continue }
          seenVirtualIds.insert(virtualId)

          let virtualShift = SharingRPCShiftRow(
            id: virtualId,
            userId: recurring.userId,
            jobId: recurring.jobId,
            shiftDate: virtual.date,
            startTime: recurring.cleanStartTime,
            endTime: recurring.cleanEndTime,
            customPauseWindows: recurring.dateSpecificPauseWindows?[virtual.date],
            customSupplements: recurring.dateSpecificSupplements?[virtual.date],
            recurringId: recurring.id,
            recurringAnchorWeekday: virtual.weekday
          )

          computed.append(
            computeShiftWithTax(
              shift: virtualShift,
              context: context,
              mode: mode
            ))
        }
      }
    }

    let overtimeAdjusted = applyOvertime(to: computed, context: context, mode: mode)
    let visible = overtimeAdjusted.filter { shift in
      shift.shiftDate >= startDate && shift.shiftDate <= endDate
    }

    let sorted = visible.sorted { lhs, rhs in
      if lhs.shiftDate == rhs.shiftDate {
        return lhs.startTime < rhs.startTime
      }
      return lhs.shiftDate < rhs.shiftDate
    }

    if mode == .hidden {
      return enforceHiddenEarnings(on: sorted)
    }

    return sorted
  }

  static func computeMonthShifts(
    payload: SharingRPCPayloadInput,
    year: Int,
    month: Int,
    mode: SharingRPCMode
  ) -> [SharingComputedShift] {
    computeShiftsInRange(
      payload: payload,
      startDate: monthStart(year: year, month: month),
      endDate: monthEnd(year: year, month: month),
      mode: mode
    )
  }

  static func payoutTaxSettings(
    year: Int,
    month: Int,
    settings: SharingRPCUserSettings,
    snapshots: [SharingRPCWageSnapshot],
    jobs: [SharingRPCJobRow],
    mode: SharingRPCMode
  ) -> SharingRPCPayoutTaxSettings? {
    guard mode == .visible else { return nil }
    let context = makePayrollContext(
      settings: settings,
      snapshots: snapshots,
      jobs: jobs
    )
    let summaryJobId = context.defaultJobId
    let payrollDay =
      summaryJobId.flatMap { context.jobsById[$0]?.payrollDay } ?? settings.effectivePayrollDay
    let scopedSnapshots = snapshotsForJob(jobId: summaryJobId, context: context)

    let schedule = PayoutSchedule(
      period: summaryJobId.flatMap { context.jobsById[$0]?.payPeriod } ?? .calendarMonth,
      payrollDay: payrollDay)
    let payoutDate = schedule.payoutDate(for: monthStart(year: year, month: month))

    guard let snapshot = snapshotForDate(payoutDate, from: scopedSnapshots) else {
      return nil
    }

    return SharingRPCPayoutTaxSettings(
      enabled: snapshot.effectiveTaxEnabled,
      percentage: snapshot.effectiveTaxPercentage
    )
  }

  static func enforceHiddenEarnings(on shifts: [SharingComputedShift]) -> [SharingComputedShift] {
    shifts.map { shift in
      SharingComputedShift(
        id: shift.id,
        userId: shift.userId,
        jobId: shift.jobId,
        jobName: shift.jobName,
        jobColor: shift.jobColor,
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        customPauseWindows: shift.customPauseWindows,
        customSupplements: nil,
        recurringId: shift.recurringId,
        recurringAnchorWeekday: shift.recurringAnchorWeekday,
        computed: SharingComputedShiftComputed(
          durationHours: shift.computed.durationHours,
          paidHours: shift.computed.paidHours,
          basePay: 0,
          supplementPay: 0,
          gross: 0,
          wagePeriods: [],
          originalWagePeriods: [],
          breakAudit: shift.computed.breakAudit
        ),
        taxEnabled: false,
        taxPercentage: 0
      )
    }
  }

  static func selectPreview(
    sharerId: String,
    shifts: [SharingComputedShift],
    showEarnings: Bool,
    now: Date = Date()
  ) -> SharingComputedPreview {
    guard !shifts.isEmpty else {
      return SharingComputedPreview(
        sharerId: sharerId, shift: nil, status: nil, showEarnings: showEarnings)
    }

    let sortedShifts = shifts.sorted { lhs, rhs in
      if lhs.shiftDate == rhs.shiftDate {
        return lhs.startTime < rhs.startTime
      }
      return lhs.shiftDate < rhs.shiftDate
    }

    for shift in sortedShifts {
      guard
        let (start, end) = shiftInterval(
          shiftDate: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)
      else {
        continue
      }

      if now >= start, now <= end {
        return SharingComputedPreview(
          sharerId: sharerId, shift: shift, status: .active, showEarnings: showEarnings)
      }
    }

    for shift in sortedShifts {
      guard let start = shiftDateTime(shiftDate: shift.shiftDate, time: shift.startTime) else {
        continue
      }

      if start > now {
        return SharingComputedPreview(
          sharerId: sharerId, shift: shift, status: .upcoming, showEarnings: showEarnings)
      }
    }

    let pastShifts = sortedShifts.filter { shift in
      guard
        let (_, end) = shiftInterval(
          shiftDate: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)
      else {
        return false
      }
      return end < now
    }

    if let mostRecentPast = pastShifts.last {
      return SharingComputedPreview(
        sharerId: sharerId, shift: mostRecentPast, status: .past, showEarnings: showEarnings)
    }

    return SharingComputedPreview(
      sharerId: sharerId, shift: nil, status: nil, showEarnings: showEarnings)
  }

  static func sortPreviews(_ previews: [SharingComputedPreview]) -> [SharingComputedPreview] {
    previews.sorted { lhs, rhs in
      let priority: [SharingPreviewStatus?] = [.active, .upcoming, .past, nil]
      let lhsPriority = priority.firstIndex(where: { $0 == lhs.status }) ?? 4
      let rhsPriority = priority.firstIndex(where: { $0 == rhs.status }) ?? 4

      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      guard
        let lhsDateTime = shiftDateTime(
          shiftDate: lhs.shift?.shiftDate, time: lhs.shift?.startTime),
        let rhsDateTime = shiftDateTime(shiftDate: rhs.shift?.shiftDate, time: rhs.shift?.startTime)
      else {
        return lhs.shift != nil
      }

      if lhs.status == .upcoming {
        return lhsDateTime < rhsDateTime
      }
      if lhs.status == .past {
        return lhsDateTime > rhsDateTime
      }

      return false
    }
  }

  // MARK: - Core Calculation

  private static func computeShiftWithTax(
    shift: SharingRPCShiftRow,
    context: SharingPayrollContext,
    mode: SharingRPCMode
  ) -> SharingComputedShift {
    let effectiveJobId = shift.jobId ?? context.defaultJobId
    let payrollDay =
      effectiveJobId.flatMap { context.jobsById[$0]?.payrollDay } ?? context.fallbackPayrollDay
    let scopedSnapshots = snapshotsForJob(jobId: effectiveJobId, context: context)

    let schedule = PayoutSchedule(
      period: effectiveJobId.flatMap { context.jobsById[$0]?.payPeriod } ?? .calendarMonth,
      payrollDay: payrollDay)
    let payoutDate = schedule.payoutDate(for: shift.shiftDate)

    let wageSnapshot = snapshotForDate(shift.shiftDate, from: scopedSnapshots)
    let taxSnapshot = snapshotForDate(payoutDate, from: scopedSnapshots)

    var computed = computeShift(shift: shift, snapshot: wageSnapshot, mode: mode)

    let taxEnabled = mode == .hidden ? false : (taxSnapshot?.effectiveTaxEnabled ?? false)
    let job = effectiveJobId.flatMap { context.jobsById[$0] }
    let halfTaxMonth = job.map(\.halfTaxMonth) ?? context.fallbackHalfTaxMonth
    let payoutMonth = dateFromISO(payoutDate).map { sharingCalendar.component(.month, from: $0) }
    let savedTaxPercentage = taxSnapshot?.effectiveTaxPercentage ?? 0
    let clampedTaxPercentage =
      savedTaxPercentage.isFinite ? min(max(savedTaxPercentage, 0), 100) : 0
    let taxPercentage =
      taxEnabled
      ? clampedTaxPercentage / (halfTaxMonth != nil && halfTaxMonth == payoutMonth ? 2 : 1) : 0

    if mode == .hidden {
      computed = SharingComputedShiftComputed(
        durationHours: computed.durationHours,
        paidHours: computed.paidHours,
        basePay: 0,
        supplementPay: 0,
        gross: 0,
        wagePeriods: [],
        originalWagePeriods: [],
        breakAudit: computed.breakAudit
      )
    }

    return SharingComputedShift(
      id: shift.id,
      userId: shift.userId,
      jobId: effectiveJobId,
      jobName: job?.name,
      jobColor: job?.color,
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      customPauseWindows: shift.customPauseWindows,
      customSupplements: mode == .hidden ? nil : shift.customSupplements,
      recurringId: shift.recurringId,
      recurringAnchorWeekday: shift.recurringAnchorWeekday,
      computed: computed,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage
    )
  }

  private struct SharingOvertimeSegment {
    let shift: SharingComputedShift
    let period: SharingRPCWagePeriod
    let absoluteStart: Date
    let absoluteEnd: Date
    let shiftDayStart: Date
    let config: SharingRPCOvertimeConfig?
  }

  private struct SharingOvertimePiece {
    let shiftId: String
    let start: Date
    let period: SharingRPCWagePeriod
    let overtimeMinutes: Double
  }

  private struct SharingRateWindow {
    let from: Int
    let to: Int
    let rate: Double
  }

  private static func applyOvertime(
    to shifts: [SharingComputedShift],
    context: SharingPayrollContext,
    mode: SharingRPCMode
  ) -> [SharingComputedShift] {
    guard mode == .visible else { return shifts }

    var grouped: [String: [SharingOvertimeSegment]] = [:]
    var fallbackPieces: [String: [SharingOvertimePiece]] = [:]

    for shift in shifts {
      let scoped = snapshotsForJob(jobId: shift.jobId, context: context)
      let snapshot = snapshotForDate(shift.shiftDate, from: scoped)
      let config = runtimeOvertimeConfig(snapshot?.effectiveOvertime)
      guard let shiftDayStart = dateFromISO(shift.shiftDate) else { continue }

      for period in shift.computed.wagePeriods {
        let absoluteStart = shiftDayStart.addingTimeInterval(period.fromMin * 60)
        let absoluteEnd = shiftDayStart.addingTimeInterval(period.toMin * 60)
        guard absoluteEnd > absoluteStart else { continue }

        for (partStart, partEnd) in splitByISOWeek(start: absoluteStart, end: absoluteEnd) {
          let partPeriod = SharingRPCWagePeriod(
            fromMin: minutesBetween(shiftDayStart, partStart),
            toMin: minutesBetween(shiftDayStart, partEnd),
            baseRate: period.baseRate,
            supplementRate: period.supplementRate
          )
          let key = "\(shift.jobId ?? "__nil__")|\(isoDateString(isoWeekStart(for: partStart)))"
          let segment = SharingOvertimeSegment(
            shift: shift,
            period: partPeriod,
            absoluteStart: partStart,
            absoluteEnd: partEnd,
            shiftDayStart: shiftDayStart,
            config: config
          )
          grouped[key, default: []].append(segment)
          fallbackPieces[shift.id, default: []].append(
            SharingOvertimePiece(
              shiftId: shift.id,
              start: partStart,
              period: partPeriod,
              overtimeMinutes: 0
            ))
        }
      }
    }

    var piecesByShift: [String: [SharingOvertimePiece]] = [:]
    for segments in grouped.values {
      var cumulativeMinutes: Double = 0
      for segment in segments.sorted(by: {
        if $0.absoluteStart != $1.absoluteStart {
          return $0.absoluteStart < $1.absoluteStart
        }
        return $0.shift.id < $1.shift.id
      }) {
        for piece in applyOvertime(to: segment, cumulativeMinutes: cumulativeMinutes) {
          piecesByShift[piece.shiftId, default: []].append(piece)
        }
        cumulativeMinutes += segment.period.durationMinutes
      }
    }

    return shifts.map { shift in
      let pieces = piecesByShift[shift.id] ?? fallbackPieces[shift.id] ?? []
      guard !pieces.isEmpty else { return shift }
      return replacingPeriods(of: shift, with: pieces)
    }
  }

  private static func replacingPeriods(
    of shift: SharingComputedShift,
    with pieces: [SharingOvertimePiece]
  ) -> SharingComputedShift {
    let sortedPieces = pieces.sorted {
      if $0.start != $1.start {
        return $0.start < $1.start
      }
      return $0.period.fromMin < $1.period.fromMin
    }
    let periods = mergeAdjacentSharingPeriods(sortedPieces.map(\.period))
    let overtimeMinutes = sortedPieces.reduce(0.0) { $0 + $1.overtimeMinutes }
    let computed = recomputeSharingComputed(
      shift.computed,
      periods: periods,
      overtimeMinutes: overtimeMinutes
    )
    return SharingComputedShift(
      id: shift.id,
      userId: shift.userId,
      jobId: shift.jobId,
      jobName: shift.jobName,
      jobColor: shift.jobColor,
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      customPauseWindows: shift.customPauseWindows,
      customSupplements: shift.customSupplements,
      recurringId: shift.recurringId,
      recurringAnchorWeekday: shift.recurringAnchorWeekday,
      computed: computed,
      taxEnabled: shift.taxEnabled,
      taxPercentage: shift.taxPercentage
    )
  }

  private static func applyOvertime(
    to segment: SharingOvertimeSegment,
    cumulativeMinutes: Double
  ) -> [SharingOvertimePiece] {
    guard let config = segment.config else {
      return [
        SharingOvertimePiece(
          shiftId: segment.shift.id,
          start: segment.absoluteStart,
          period: segment.period,
          overtimeMinutes: 0
        )
      ]
    }

    let thresholdMinutes = config.weeklyThresholdHours * 60
    var cursor = segment.absoluteStart
    var cursorCumulative = cumulativeMinutes
    var pieces: [SharingOvertimePiece] = []

    while cursor < segment.absoluteEnd {
      let next = nextSharingOvertimeBoundary(
        after: cursor,
        segmentEnd: segment.absoluteEnd,
        config: config,
        cumulativeMinutes: cursorCumulative,
        thresholdMinutes: thresholdMinutes
      )
      let durationMinutes = minutesBetween(cursor, next)
      guard durationMinutes > 0 else { break }

      let percent =
        cursorCumulative >= thresholdMinutes
        ? sharingOvertimePercent(config: config, at: cursor)
        : nil
      let supplementRate =
        percent.map { segment.period.baseRate * $0 / 100 }
        ?? segment.period.supplementRate

      pieces.append(
        SharingOvertimePiece(
          shiftId: segment.shift.id,
          start: cursor,
          period: SharingRPCWagePeriod(
            fromMin: minutesBetween(segment.shiftDayStart, cursor),
            toMin: minutesBetween(segment.shiftDayStart, next),
            baseRate: segment.period.baseRate,
            supplementRate: supplementRate,
            isOvertime: percent != nil
          ),
          overtimeMinutes: percent == nil ? 0 : durationMinutes
        ))

      cursorCumulative += durationMinutes
      cursor = next
    }

    return pieces
  }

  private static func recomputeSharingComputed(
    _ computed: SharingComputedShiftComputed,
    periods: [SharingRPCWagePeriod],
    overtimeMinutes: Double
  ) -> SharingComputedShiftComputed {
    var basePay: Double = 0
    var supplementPay: Double = 0

    for period in periods {
      basePay += max(0, period.durationHours) * period.baseRate
      supplementPay += max(0, period.durationHours) * period.supplementRate
    }

    basePay = roundedPay(basePay, periodCount: periods.count)
    supplementPay = roundedPay(supplementPay, periodCount: periods.count)
    return SharingComputedShiftComputed(
      durationHours: computed.durationHours,
      paidHours: computed.paidHours,
      basePay: basePay,
      supplementPay: supplementPay,
      gross: roundTo(basePay + supplementPay, decimals: 2),
      wagePeriods: periods,
      originalWagePeriods: computed.originalWagePeriods,
      breakAudit: computed.breakAudit,
      overtimeApplied: overtimeMinutes > 0,
      overtimeMinutes: roundTo(overtimeMinutes, decimals: 2)
    )
  }

  private static func runtimeOvertimeConfig(_ config: SharingRPCOvertimeConfig?)
    -> SharingRPCOvertimeConfig?
  {
    guard let config, config.enabled, config.weeklyThresholdHours.isFinite,
      config.weeklyThresholdHours > 0, !config.rules.isEmpty
    else {
      return nil
    }
    guard config.rules.allSatisfy(isValidSharingOvertimeRule),
      sharingRulesCoverFullDay(config.rules, holiday: false),
      sharingRulesCoverFullDay(config.rules, holiday: true)
    else {
      return nil
    }
    return config
  }

  private nonisolated static func isValidSharingOvertimeRule(_ rule: SharingRPCOvertimeRule) -> Bool
  {
    guard !rule.days.isEmpty,
      Set(rule.days).isSubset(of: Set(1...7)),
      rule.percent.isFinite,
      rule.percent > 0,
      let from = timeToMinutes(rule.from),
      let to = timeToMinutes(rule.to)
    else {
      return false
    }
    return from < to && to <= 24 * 60
  }

  private static func sharingRulesCoverFullDay(
    _ rules: [SharingRPCOvertimeRule],
    holiday: Bool
  ) -> Bool {
    for day in 1...7 {
      let intervals = rules.compactMap { rule -> (Int, Int)? in
        guard rule.days.contains(day) else {
          return nil
        }
        if holiday {
          guard rule.appliesOnHolidays else { return nil }
        } else if isHolidayOnlyRule(rule) {
          return nil
        }
        guard let from = timeToMinutes(rule.from),
          let to = timeToMinutes(rule.to)
        else {
          return nil
        }
        return (from, to)
      }
      guard intervalsCoverFullDay(intervals) else { return false }
    }
    return true
  }

  private static func nextSharingOvertimeBoundary(
    after date: Date,
    segmentEnd: Date,
    config: SharingRPCOvertimeConfig,
    cumulativeMinutes: Double,
    thresholdMinutes: Double
  ) -> Date {
    var boundary = segmentEnd
    let dayStart = sharingCalendar.startOfDay(for: date)

    if let nextDay = sharingCalendar.date(byAdding: .day, value: 1, to: dayStart),
      nextDay > date
    {
      boundary = min(boundary, nextDay)
    }

    if cumulativeMinutes < thresholdMinutes {
      let thresholdDate = date.addingTimeInterval((thresholdMinutes - cumulativeMinutes) * 60)
      if thresholdDate > date {
        boundary = min(boundary, thresholdDate)
      }
    }

    let minuteOfDay = minutesBetween(dayStart, date)
    for rule in config.rules where sharingOvertimeRuleCanMatch(rule, at: date) {
      guard let from = timeToMinutes(rule.from), let to = timeToMinutes(rule.to) else {
        continue
      }
      for value in [Double(from), Double(to)] where value > minuteOfDay {
        let candidate = dayStart.addingTimeInterval(value * 60)
        if candidate > date {
          boundary = min(boundary, candidate)
        }
      }
    }

    return boundary
  }

  private static func sharingOvertimePercent(
    config: SharingRPCOvertimeConfig,
    at date: Date
  ) -> Double? {
    let minute = minutesBetween(sharingCalendar.startOfDay(for: date), date)
    return config.rules.compactMap { rule -> Double? in
      guard sharingOvertimeRuleCanMatch(rule, at: date),
        let from = timeToMinutes(rule.from),
        let to = timeToMinutes(rule.to),
        minute >= Double(from),
        minute < Double(to)
      else {
        return nil
      }
      return rule.percent
    }.max()
  }

  private static func sharingOvertimeRuleCanMatch(
    _ rule: SharingRPCOvertimeRule,
    at date: Date
  ) -> Bool {
    guard rule.days.contains(weekday(from: date)) else { return false }
    if isNorwegianPublicHoliday(date) {
      return rule.appliesOnHolidays
    }
    return !isHolidayOnlyRule(rule)
  }

  private static func isNorwegianPublicHoliday(_ date: Date) -> Bool {
    let components = sharingCalendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return false
    }

    let fixedHolidays: Set<String> = ["01-01", "05-01", "05-17", "12-25", "12-26"]
    if fixedHolidays.contains(String(format: "%02d-%02d", month, day)) {
      return true
    }

    guard let easter = easterSunday(year: year) else { return false }
    let holidayOffsets = [-3, -2, 0, 1, 39, 49, 50]
    return holidayOffsets.contains { offset in
      guard let holiday = sharingCalendar.date(byAdding: .day, value: offset, to: easter) else {
        return false
      }
      return sharingCalendar.isDate(holiday, inSameDayAs: date)
    }
  }

  private static func easterSunday(year: Int) -> Date? {
    let a = year % 19
    let b = year / 100
    let c = year % 100
    let d = b / 4
    let e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4
    let k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31
    let day = ((h + l - 7 * m + 114) % 31) + 1
    return sharingCalendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  private static func isHolidayOnlyRule(_ rule: SharingRPCOvertimeRule) -> Bool {
    rule.appliesOnHolidays && Set(rule.days) == Set(1...7)
  }

  private static func intervalsCoverFullDay(_ intervals: [(Int, Int)]) -> Bool {
    var coveredUntil = 0
    for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
      guard interval.0 <= coveredUntil else { return false }
      coveredUntil = max(coveredUntil, interval.1)
      if coveredUntil >= 24 * 60 {
        return true
      }
    }
    return false
  }

  private nonisolated static func timeToMinutes(_ value: String) -> Int? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      minutes >= 0,
      minutes < 60,
      hours >= 0,
      hours <= 24,
      hours < 24 || minutes == 0
    else {
      return nil
    }
    return hours * 60 + minutes
  }

  private static func splitByISOWeek(start: Date, end: Date) -> [(Date, Date)] {
    var result: [(Date, Date)] = []
    var cursor = start

    while cursor < end {
      let weekEnd =
        sharingISOCalendar.date(byAdding: .day, value: 7, to: isoWeekStart(for: cursor))
        ?? end
      let partEnd = min(end, weekEnd)
      result.append((cursor, partEnd))
      cursor = partEnd
    }

    return result
  }

  private static func isoWeekStart(for date: Date) -> Date {
    sharingISOCalendar.dateInterval(of: .weekOfYear, for: date)?.start
      ?? sharingCalendar.startOfDay(for: date)
  }

  private static func expandedISOWeekRange(startDate: String, endDate: String) -> (
    startDate: String, endDate: String
  ) {
    guard let start = dateFromISO(startDate), let end = dateFromISO(endDate) else {
      return (startDate, endDate)
    }
    let expandedStart = isoWeekStart(for: start)
    let endWeekStart = isoWeekStart(for: end)
    let expandedEnd = sharingISOCalendar.date(byAdding: .day, value: 6, to: endWeekStart) ?? end
    return (isoDateString(expandedStart), isoDateString(expandedEnd))
  }

  private static func weekday(from date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let value = calendar.component(.weekday, from: date)
    return value == 1 ? 7 : value - 1
  }

  private static func minutesBetween(_ start: Date, _ end: Date) -> Double {
    end.timeIntervalSince(start) / 60
  }

  private static func mergeAdjacentSharingPeriods(_ periods: [SharingRPCWagePeriod])
    -> [SharingRPCWagePeriod]
  {
    var merged: [SharingRPCWagePeriod] = []
    for period in periods where period.toMin > period.fromMin {
      if let last = merged.last,
        abs(last.toMin - period.fromMin) < 0.0001,
        last.baseRate == period.baseRate,
        last.supplementRate == period.supplementRate,
        last.isOvertime == period.isOvertime
      {
        merged[merged.count - 1] = SharingRPCWagePeriod(
          fromMin: last.fromMin,
          toMin: period.toMin,
          baseRate: last.baseRate,
          supplementRate: last.supplementRate,
          isOvertime: last.isOvertime
        )
      } else {
        merged.append(period)
      }
    }
    return merged
  }

  private static let sharingCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }()

  private static let sharingISOCalendar: Calendar = {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = .current
    return calendar
  }()

  private static func makePayrollContext(
    settings: SharingRPCUserSettings,
    snapshots: [SharingRPCWageSnapshot],
    jobs: [SharingRPCJobRow]
  ) -> SharingPayrollContext {
    let activeJobs = jobs.filter { $0.deletedAt == nil }
    let jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
    let defaultJobId =
      activeJobs.first(where: { $0.isDefault && $0.archivedAt == nil })?.id
      ?? activeJobs.first(where: \.isDefault)?.id
      ?? activeJobs.first?.id
      ?? jobs.first(where: { $0.isDefault && $0.archivedAt == nil })?.id
      ?? jobs.first(where: \.isDefault)?.id
      ?? jobs.first?.id
    let snapshotsByJobId = Dictionary(grouping: snapshots, by: { $0.jobId })
    let legacyNilJobSnapshots = snapshotsByJobId[nil] ?? []

    return SharingPayrollContext(
      fallbackPayrollDay: settings.effectivePayrollDay,
      fallbackHalfTaxMonth: settings.halfTaxMonth,
      jobsById: jobsById,
      defaultJobId: defaultJobId,
      snapshotsByJobId: snapshotsByJobId,
      legacyNilJobSnapshots: legacyNilJobSnapshots,
      allSnapshots: snapshots
    )
  }

  private static func snapshotsForJob(
    jobId: String?,
    context: SharingPayrollContext
  ) -> [SharingRPCWageSnapshot] {
    if let jobId, let scoped = context.snapshotsByJobId[jobId], !scoped.isEmpty {
      return scoped
    }

    if !context.legacyNilJobSnapshots.isEmpty {
      return context.legacyNilJobSnapshots
    }

    if let defaultJobId = context.defaultJobId,
      let defaultScoped = context.snapshotsByJobId[defaultJobId],
      !defaultScoped.isEmpty
    {
      return defaultScoped
    }

    return context.allSnapshots
  }

  private static func computeShift(
    shift: SharingRPCShiftRow,
    snapshot: SharingRPCWageSnapshot?,
    mode: SharingRPCMode
  ) -> SharingComputedShiftComputed {
    let weekday = weekdayFromISO(shift.shiftDate)
    let normalizedPauseWindows = PauseWindowSupport.normalize(shift.customPauseWindows)

    let baseRate = resolveBaseRate(snapshot: snapshot, mode: mode)
    let rules = resolveSupplementRules(
      snapshot: snapshot,
      customSupplements: shift.customSupplements,
      mode: mode
    )

    var periods = buildWagePeriods(
      startTime: shift.startTime,
      endTime: shift.endTime,
      weekday: weekday,
      baseRate: baseRate,
      rules: rules
    )
    let originalPeriods = periods

    let totalMinutes = periods.reduce(0.0) { $0 + $1.durationMinutes }
    let durationHours = totalMinutes / 60.0
    let breakAudit: SharingRPCBreakAudit

    if let normalizedPauseWindows {
      let clipped = PauseWindowSupport.apply(
        customPauseWindows: normalizedPauseWindows,
        startTime: shift.startTime,
        endTime: shift.endTime,
        periods: periods.map {
          PauseClipPeriod(
            fromMin: $0.fromMin,
            toMin: $0.toMin,
            baseRate: $0.baseRate,
            supplementRate: $0.supplementRate
          )
        }
      )
      periods = clipped.periods.map {
        SharingRPCWagePeriod(
          fromMin: $0.fromMin,
          toMin: $0.toMin,
          baseRate: $0.baseRate,
          supplementRate: $0.supplementRate
        )
      }
      breakAudit = SharingRPCBreakAudit(
        method: .none,
        thresholdHours: 0,
        deductedHours: clipped.deductedHours,
        source: .customPauseWindows,
        appliedPauseWindows: clipped.appliedPauseWindows,
        notes: clipped.appliedPauseWindows?.isEmpty == false
          ? ["Deducted using custom pause windows"] : []
      )
    } else {
      let breakEnabled = snapshot?.effectiveBreakEnabled ?? defaultBreakEnabled
      let breakMethod = snapshot?.effectiveBreakMethod ?? .proportional
      let breakThreshold = snapshot?.effectiveBreakThresholdHours ?? defaultBreakThresholdHours
      let breakMinutes =
        breakEnabled
        ? (snapshot?.effectiveBreakDeductionMinutes ?? defaultBreakDeductionMinutes) : 0

      let breakResult = applyBreakDeduction(
        periods: periods,
        method: breakMethod,
        thresholdHours: breakThreshold,
        deductionHours: Double(breakMinutes) / 60.0
      )

      periods = breakResult.periods
      breakAudit = breakResult.audit
    }

    let paidMinutes = periods.reduce(0.0) { $0 + $1.durationMinutes }
    let paidHours = paidMinutes / 60.0

    var basePay: Double = 0
    var supplementPay: Double = 0

    for period in periods {
      basePay += max(0, period.durationHours) * period.baseRate
      supplementPay += max(0, period.durationHours) * period.supplementRate
    }

    basePay = roundedPay(basePay, periodCount: periods.count)
    supplementPay = roundedPay(supplementPay, periodCount: periods.count)
    let gross = roundTo(basePay + supplementPay, decimals: 2)

    return SharingComputedShiftComputed(
      durationHours: durationHours,
      paidHours: paidHours,
      basePay: basePay,
      supplementPay: supplementPay,
      gross: gross,
      wagePeriods: mode == .hidden ? [] : periods,
      originalWagePeriods: mode == .hidden ? [] : originalPeriods,
      breakAudit: breakAudit
    )
  }

  private static func resolveBaseRate(snapshot: SharingRPCWageSnapshot?, mode: SharingRPCMode)
    -> Double
  {
    if let wage = snapshot?.hourlyWage, wage.isFinite, wage > 0 {
      return wage
    }

    if mode == .hidden {
      return 0
    }

    return fallbackBaseRate
  }

  private static func resolveSupplementRules(
    snapshot: SharingRPCWageSnapshot?,
    customSupplements: SharingRPCCustomSupplements?,
    mode: SharingRPCMode
  ) -> [SharingRPCSupplementRule] {
    if let customSupplements {
      if customSupplements.rules.isEmpty {
        return []
      }

      return customSupplements.rules.map { rule in
        SharingRPCSupplementRule(
          days: Array(1...7),
          from: rule.from,
          to: rule.to,
          rate: rule.rate,
          percent: rule.percent
        )
      }
    }

    if let snapshot {
      return snapshot.supplements.rules
    }

    if mode == .hidden {
      return []
    }

    return presetSupplementRules
  }

  // MARK: - Wage Periods + Break Deduction

  private static func buildWagePeriods(
    startTime: String,
    endTime: String,
    weekday: Int,
    baseRate: Double,
    rules: [SharingRPCSupplementRule]
  ) -> [SharingRPCWagePeriod] {
    guard let start = timeToMinutes(startTime), var end = timeToMinutes(endTime) else { return [] }
    if end <= start { end += 24 * 60 }

    var windows: [SharingRateWindow] = []
    for rule in rules {
      guard let from = timeToMinutes(rule.from), let to = timeToMinutes(rule.to), from != to else {
        continue
      }
      for dayOffset in -1...1 {
        let ruleWeekday = (weekday - 1 + dayOffset + 7) % 7 + 1
        guard rule.days.contains(ruleWeekday) else { continue }
        let windowFrom = from + dayOffset * 24 * 60
        let windowTo = to + dayOffset * 24 * 60 + (to < from ? 24 * 60 : 0)
        guard windowTo > start, windowFrom < end else { continue }
        windows.append(
          SharingRateWindow(
            from: windowFrom, to: windowTo,
            rate: resolveSupplementRate(rule: rule, baseRate: baseRate)))
      }
    }
    var points = Set([start, end])
    for window in windows {
      points.insert(max(start, window.from))
      points.insert(min(end, window.to))
    }
    let sorted = points.sorted()
    return zip(sorted, sorted.dropFirst()).map { from, to in
      let supplement = windows.filter { from >= $0.from && to <= $0.to }.map(\.rate).max() ?? 0
      return SharingRPCWagePeriod(
        fromMin: Double(from), toMin: Double(to), baseRate: baseRate, supplementRate: supplement
      )
    }
  }

  private static func applyBreakDeduction(
    periods: [SharingRPCWagePeriod],
    method: SharingRPCBreakMethod,
    thresholdHours: Double,
    deductionHours: Double
  ) -> SharingRPCBreakDeductionResult {
    let totalMinutes = periods.reduce(0.0) { $0 + max(0, $1.durationMinutes) }
    let totalHours = totalMinutes / 60.0

    let thresholdHours = thresholdHours.isFinite ? max(0, thresholdHours) : totalHours
    let sanitizedDeduction = deductionHours.isFinite ? min(max(0, deductionHours), totalHours) : 0
    let toDeduct = method != .none && totalHours > thresholdHours ? sanitizedDeduction : 0

    var adjusted = periods
    var notes: [String] = []

    if toDeduct > 0, method != .none {
      var remaining = (toDeduct * 60).rounded()

      switch method {
      case .endOfShift:
        for idx in stride(from: adjusted.count - 1, through: 0, by: -1) {
          guard remaining > 0 else { break }
          let span = adjusted[idx].durationMinutes
          let cut = min(span, remaining)

          adjusted[idx] = SharingRPCWagePeriod(
            fromMin: adjusted[idx].fromMin,
            toMin: adjusted[idx].toMin - cut,
            baseRate: adjusted[idx].baseRate,
            supplementRate: adjusted[idx].supplementRate
          )

          remaining -= cut
        }
        notes.append("Deducted at end of shift")

      case .proportional:
        var newPeriods: [SharingRPCWagePeriod] = []

        for period in adjusted {
          let proportion = period.durationMinutes / totalMinutes
          let cutMinutes = proportion * toDeduct * 60

          newPeriods.append(
            SharingRPCWagePeriod(
              fromMin: period.fromMin,
              toMin: period.toMin - cutMinutes,
              baseRate: period.baseRate,
              supplementRate: period.supplementRate
            )
          )
        }

        adjusted = newPeriods
        notes.append("Deducted proportionally across periods")

      case .baseOnly:
        let sortedIndices = adjusted.indices.sorted {
          adjusted[$0].supplementRate < adjusted[$1].supplementRate
        }

        for idx in sortedIndices {
          guard remaining > 0 else { break }
          let span = adjusted[idx].durationMinutes
          let cut = min(span, remaining)

          adjusted[idx] = SharingRPCWagePeriod(
            fromMin: adjusted[idx].fromMin,
            toMin: adjusted[idx].toMin - cut,
            baseRate: adjusted[idx].baseRate,
            supplementRate: adjusted[idx].supplementRate
          )

          remaining -= cut
        }
        notes.append("Deducted from base/lowest supplement periods first")

      case .none:
        break
      }

      adjusted = adjusted.filter { $0.toMin > $0.fromMin }
    }

    let paidMinutes = adjusted.reduce(0.0) { $0 + max(0, $1.durationMinutes) }
    let deductedHours = max(0, totalMinutes - paidMinutes) / 60
    return SharingRPCBreakDeductionResult(
      periods: adjusted,
      audit: SharingRPCBreakAudit(
        method: method,
        thresholdHours: thresholdHours,
        deductedHours: deductedHours,
        source: deductedHours > 0 ? .automaticBreak : .none,
        appliedPauseWindows: nil,
        notes: notes
      )
    )
  }

  private static func resolveSupplementRate(rule: SharingRPCSupplementRule, baseRate: Double)
    -> Double
  {
    if let rate = rule.rate, rate.isFinite, rate >= 0 {
      return rate
    }

    if let percent = rule.percent, percent.isFinite, percent >= 0 {
      return (baseRate * percent) / 100.0
    }

    return 0
  }

  // MARK: - Snapshot Helpers

  private static func snapshotForDate(
    _ date: String,
    from snapshots: [SharingRPCWageSnapshot]
  ) -> SharingRPCWageSnapshot? {
    let baseline = snapshots.first { $0.fromDate == nil }

    let dated =
      snapshots
      .filter { $0.fromDate != nil }
      .sorted { ($0.fromDate ?? "") < ($1.fromDate ?? "") }

    var left = 0
    var right = dated.count - 1
    var result: SharingRPCWageSnapshot?

    while left <= right {
      let mid = (left + right) / 2
      if let midDate = dated[mid].fromDate, midDate <= date {
        result = dated[mid]
        left = mid + 1
      } else {
        right = mid - 1
      }
    }

    return result ?? baseline
  }

  // MARK: - Recurring Helpers

  private static func generateVirtualShiftsForMonth(
    year: Int,
    month: Int,
    recurring: SharingRPCRecurringShiftRow
  ) -> [SharingRecurringVirtualShift] {
    guard !recurring.selectedDays.isEmpty else { return [] }

    let monthStartISO = monthStart(year: year, month: month)
    let monthEndISO = monthEnd(year: year, month: month)
    let exclusionSet = Set(recurring.exclusions ?? [])

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    var startComponents = DateComponents()
    startComponents.year = year
    startComponents.month = month
    startComponents.day = 1
    startComponents.hour = 12

    var endComponents = DateComponents()
    endComponents.year = year
    endComponents.month = month
    endComponents.day = daysInMonth(year: year, month: month)
    endComponents.hour = 12

    guard let monthStartDate = calendar.date(from: startComponents),
      let monthEndDate = calendar.date(from: endComponents)
    else {
      return []
    }

    var virtualShifts: [SharingRecurringVirtualShift] = []

    for (weekdayKey, anchorISO) in recurring.selectedDays {
      guard let weekday = Int(weekdayKey) else { continue }

      var current = monthStartDate
      let currentWeekday = calendar.component(.weekday, from: current) - 1
      let daysUntilTarget = (weekday - currentWeekday + 7) % 7
      current = calendar.date(byAdding: .day, value: daysUntilTarget, to: current) ?? current

      while current <= monthEndDate {
        let currentISO = isoDateString(current)

        if currentISO < monthStartISO || currentISO > monthEndISO {
          current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
          continue
        }

        if currentISO < anchorISO {
          current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
          continue
        }

        let inPhase = isInPhase(
          dateISO: currentISO,
          anchorISO: anchorISO,
          interval: recurring.repeatIntervalWeeks
        )

        let withinWindow = checkEndCondition(
          currentDate: current,
          currentISO: currentISO,
          endCondition: recurring.endCondition,
          selectedDays: recurring.selectedDays
        )

        let notExcluded = !exclusionSet.contains(currentISO)

        if inPhase, withinWindow, notExcluded {
          virtualShifts.append(SharingRecurringVirtualShift(date: currentISO, weekday: weekday))
        }

        current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
      }
    }

    return virtualShifts.sorted { $0.date < $1.date }
  }

  private static func isInPhase(dateISO: String, anchorISO: String, interval: Int) -> Bool {
    if interval == 0 { return true }
    let dayDiff = daysBetween(anchorISO, dateISO)
    let weeksDiff = dayDiff / 7
    return weeksDiff.isMultiple(of: interval + 1)
  }

  private static func checkEndCondition(
    currentDate: Date,
    currentISO: String,
    endCondition: SharingRPCEndCondition?,
    selectedDays: [String: String]
  ) -> Bool {
    guard let endCondition else {
      return true
    }

    let anchorDates = selectedDays.values.sorted()
    guard let earliestAnchor = anchorDates.first,
      let anchorDate = dateFromISO(earliestAnchor)
    else {
      return true
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    switch endCondition {
    case .months(let value):
      guard let endDate = calendar.date(byAdding: .month, value: value, to: anchorDate) else {
        return true
      }
      return currentDate <= endDate

    case .years(let value):
      guard let endDate = calendar.date(byAdding: .year, value: value, to: anchorDate) else {
        return true
      }
      return currentDate <= endDate

    case .endDate(let date):
      return currentISO <= date
    }
  }

  // MARK: - Date + Time Helpers

  private static func shiftInterval(
    shiftDate: String,
    startTime: String,
    endTime: String
  ) -> (start: Date, end: Date)? {
    guard let start = shiftDateTime(shiftDate: shiftDate, time: startTime),
      var end = shiftDateTime(shiftDate: shiftDate, time: endTime)
    else {
      return nil
    }

    if end <= start {
      end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: end) ?? end
    }

    return (start, end)
  }

  private static func shiftDateTime(shiftDate: String?, time: String?) -> Date? {
    guard let shiftDate, let time else { return nil }

    let dateParts = shiftDate.split(separator: "-").compactMap { Int($0) }
    let timeParts = time.split(separator: ":").compactMap { Int($0) }

    guard dateParts.count == 3, timeParts.count >= 2 else { return nil }

    let hour = timeParts[0] == 24 ? 0 : timeParts[0]

    var components = DateComponents()
    components.year = dateParts[0]
    components.month = dateParts[1]
    components.day = dateParts[2]
    components.hour = hour
    components.minute = timeParts[1]
    components.second = 0
    components.timeZone = .current

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    guard var date = calendar.date(from: components) else { return nil }

    if timeParts[0] == 24 {
      date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    return date
  }

  private static func weekdayFromISO(_ dateString: String) -> Int {
    guard let date = dateFromISO(dateString) else { return 1 }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let weekday = calendar.component(.weekday, from: date)
    return weekday == 1 ? 7 : weekday - 1
  }

  private static func dateFromISO(_ dateString: String) -> Date? {
    isoDateFormatter.date(from: dateString)
  }

  private static func daysBetween(_ from: String, _ to: String) -> Int {
    guard let fromDate = dateFromISO(from),
      let toDate = dateFromISO(to)
    else {
      return 0
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    let fromStart = calendar.startOfDay(for: fromDate)
    let toStart = calendar.startOfDay(for: toDate)

    return calendar.dateComponents([.day], from: fromStart, to: toStart).day ?? 0
  }

  private static func monthsInRange(startDate: String, endDate: String) -> [(Int, Int)] {
    let startParts = startDate.split(separator: "-")
    let endParts = endDate.split(separator: "-")

    guard startParts.count >= 2,
      endParts.count >= 2,
      let startYear = Int(startParts[0]),
      let startMonth = Int(startParts[1]),
      let endYear = Int(endParts[0]),
      let endMonth = Int(endParts[1])
    else {
      return []
    }

    var result: [(Int, Int)] = []
    var year = startYear
    var month = startMonth

    while year < endYear || (year == endYear && month <= endMonth) {
      result.append((year, month))
      month += 1
      if month > 12 {
        month = 1
        year += 1
      }
    }

    return result
  }

  private static func daysInMonth(year: Int, month: Int) -> Int {
    var components = DateComponents()
    components.year = year
    components.month = month + 1
    components.day = 0

    let calendar = Calendar(identifier: .gregorian)
    guard let date = calendar.date(from: components) else {
      return 30
    }

    return calendar.component(.day, from: date)
  }

  private static func roundedPay(_ amount: Double, periodCount: Int) -> Double {
    let cents = amount * 100
    // Allow for floating-point error from each contribution and the final scaling.
    let tolerance = abs(cents) * Double.ulpOfOne * Double(periodCount + 2)
    return round(cents + tolerance) / 100
  }

  private static func roundTo(_ value: Double, decimals: Int) -> Double {
    let precision = pow(10.0, Double(decimals))
    return round(value * precision) / precision
  }
}

// MARK: - Widget Shift Status

/// Status of a shift preview
/// Note: This mirrors the app's ShiftPreviewStatus but is local to shared extension code.
enum FriendShiftStatus: String, Codable, Sendable {
  case active
  case upcoming
  case past
}

// MARK: - Combined Friends Data

/// Combined data for a friend with their shift preview
/// Shift data for the friends widget.
struct FriendWithShift: Sendable {
  let id: String
  let displayName: String
  let initials: String
  let profilePictureUrl: String?
  let oauthAvatarUrl: String?
  let showEarnings: Bool
  let hidden: Bool

  // Shift data (if available)
  let shiftId: String?
  let shiftDate: String?
  let startTime: String?
  let endTime: String?
  let gross: Double?
  let status: FriendShiftStatus?

  /// Whether this friend has a shift to display
  var hasShift: Bool {
    shiftId != nil
  }

  /// Effective avatar URL (profile picture takes precedence)
  var effectiveAvatarURL: URL? {
    if let urlString = profilePictureUrl ?? oauthAvatarUrl,
      !urlString.isEmpty
    {
      return URL(string: urlString)
    }
    return nil
  }
}

// MARK: - Errors

enum FriendsAPIError: Error, LocalizedError, Sendable {
  case noAccessToken
  case noAnonKey
  case networkError(underlying: String)
  case offline
  case httpError(statusCode: Int)
  case decodingError(underlying: String)
  case unauthorized

  /// Maps a transport failure to `.offline` when the device has no usable connection.
  /// The share extension can't reach `AuthSessionManager`, so it keeps its own code list.
  static func transportError(_ error: Error) -> FriendsAPIError {
    let offlineCodes: Set<URLError.Code> = [
      .timedOut,
      .cannotFindHost,
      .cannotConnectToHost,
      .networkConnectionLost,
      .dnsLookupFailed,
      .notConnectedToInternet,
      .internationalRoamingOff,
      .callIsActive,
      .dataNotAllowed,
    ]
    if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
      return .offline
    }
    return .networkError(underlying: error.localizedDescription)
  }

  /// User-facing text. The `underlying` strings are English diagnostics and stay out of it.
  var errorDescription: String? {
    switch self {
    case .noAccessToken, .unauthorized:
      return String(localized: .shareErrorSignInRequired)

    case .offline:
      return String(localized: .shareErrorOffline)

    case .noAnonKey, .networkError, .httpError, .decodingError:
      return String(localized: .shareErrorRequestFailed)
    }
  }
}

// MARK: - RPC Error Response

private struct RPCErrorResponse: Codable {
  let code: String?
  let message: String?
  let details: String?
  let hint: String?
}

// MARK: - Friends API Client

/// Lightweight API client for fetching friends data directly
/// Fetches friend data for widgets without launching the main app.
///
/// This client fetches from the consolidated Supabase Friends bootstrap RPC.
///
/// Preview selection and payroll computation are handled client-side via SharingComputeCore.
enum FriendsAPIClient {
  /// Base URL for Supabase REST RPC
  private static let rpcBaseURL = URL(string: "https://api.tidex.no/rest/v1/rpc")

  /// Fallback anon/publishable key for extension contexts lacking Info.plist config
  private static let fallbackAnonKey = "sb_publishable_z9EoG7GZZMS3RL4hmilh5A_xI0va5Nb"

  /// Shared URLSession with reasonable timeouts
  fileprivate static let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
  }()

  /// Supabase anon key from Info.plist (or fallback)
  fileprivate static var supabaseAnonKey: String {
    if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
      !key.isEmpty
    {
      return key
    }
    return fallbackAnonKey
  }

  // MARK: - Public API

  /// Fetch all friends with their shift previews in a single call
  /// Main entry point for the friends widget.
  /// - Returns: Array of friends with their shift data
  static func fetchFriendsWithShifts() async throws -> [FriendWithShift] {
    guard let accessToken = SharedKeychainStorage.getValidAccessToken() else {
      throw FriendsAPIError.noAccessToken
    }

    guard !supabaseAnonKey.isEmpty else {
      throw FriendsAPIError.noAnonKey
    }

    let now = Date()
    let startDate = SharingComputeCore.isoDateString(
      Calendar.gregorianCurrent.date(byAdding: .day, value: -30, to: now) ?? now)
    let endDate = SharingComputeCore.isoDateString(
      Calendar.gregorianCurrent.date(byAdding: .day, value: 30, to: now) ?? now)

    let bootstrap = try await fetchFriendsTabBootstrap(
      startDate: startDate,
      endDate: endDate,
      accessToken: accessToken
    )
    let sharers = bootstrap.sharers
    let activeSharers = sharers.filter { !$0.hidden }

    guard !activeSharers.isEmpty else {
      return []
    }

    let activeSharerIds = Set(activeSharers.map(\.id))
    let payloadRows = bootstrap.previewPayloads.filter { activeSharerIds.contains($0.sharerId) }

    let rowsBySharerId = Dictionary(
      payloadRows.map { ($0.sharerId, $0) }, uniquingKeysWith: { _, last in last })

    var previews: [SharingComputedPreview] = []
    previews.reserveCapacity(activeSharers.count)

    for sharer in activeSharers {
      if let payloadRow = rowsBySharerId[sharer.id] {
        let mode: SharingRPCMode = payloadRow.showEarnings ? .visible : .hidden
        let shifts = SharingComputeCore.computeShiftsInRange(
          payload: payloadRow.payloadInput,
          startDate: startDate,
          endDate: endDate,
          mode: mode
        )
        previews.append(
          SharingComputeCore.selectPreview(
            sharerId: sharer.id,
            shifts: shifts,
            showEarnings: payloadRow.showEarnings,
            now: now
          ))
      } else {
        // Defense: no row means no share access or no data
        previews.append(
          SharingComputedPreview(
            sharerId: sharer.id,
            shift: nil,
            status: nil,
            showEarnings: false
          ))
      }
    }

    let sortedPreviews = SharingComputeCore.sortPreviews(previews)
    let previewMap = Dictionary(
      sortedPreviews.map { ($0.sharerId, $0) }, uniquingKeysWith: { _, last in last })

    let results = activeSharers.map { sharer in
      let preview = previewMap[sharer.id]
      let status = preview?.status.flatMap { FriendShiftStatus(rawValue: $0.rawValue) }

      let showEarnings = preview?.showEarnings ?? sharer.showEarnings
      let previewShift = preview?.shift
      let safeGross = showEarnings ? previewShift?.computed.gross : nil

      return FriendWithShift(
        id: sharer.id,
        displayName: sharer.firstName ?? formattedUsername(sharer.username)
          ?? sharer.email?.components(separatedBy: "@").first
          ?? "Unknown",
        initials: makeInitials(
          from: sharer.firstName ?? sharer.username ?? sharer.email?.components(separatedBy: "@")
            .first
            ?? "?"
        ),
        profilePictureUrl: sharer.profilePictureUrl,
        oauthAvatarUrl: sharer.oauthAvatarUrl,
        showEarnings: showEarnings,
        hidden: sharer.hidden,
        shiftId: previewShift?.id,
        shiftDate: previewShift?.shiftDate,
        startTime: previewShift?.startTime,
        endTime: previewShift?.endTime,
        gross: safeGross,
        status: status
      )
    }

    return sortFriends(results)
  }

  // MARK: - Private API Methods

  private static func fetchFriendsTabBootstrap(
    startDate: String,
    endDate: String,
    accessToken: String
  ) async throws -> FriendsTabBootstrapRPCResponse {
    try await callRPC(
      functionName: "get_friends_tab_bootstrap",
      body: [
        "p_preview_start_date": startDate,
        "p_preview_end_date": endDate,
      ],
      accessToken: accessToken,
      expectsSingleObject: true
    )
  }

  private struct FriendsTabBootstrapRPCResponse: Decodable, Sendable {
    let sharers: [BootstrapSharerRow]
    let previewPayloads: [SharingRPCPreviewPayloadRow]
  }

  private struct BootstrapSharerRow: Decodable, Sendable {
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
  }

  fileprivate static func callRPC<T: Decodable>(
    functionName: String,
    body: [String: Any],
    accessToken: String,
    expectsSingleObject: Bool = false
  ) async throws -> T {
    guard let rpcBaseURL else {
      throw FriendsAPIError.networkError(underlying: "Invalid RPC base URL")
    }

    let url = rpcBaseURL.appendingPathComponent(functionName)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      expectsSingleObject ? "application/vnd.pgrst.object+json" : "application/json",
      forHTTPHeaderField: "Accept"
    )

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    } catch {
      throw FriendsAPIError.networkError(
        underlying: "Failed to encode RPC body: \(error.localizedDescription)")
    }

    do {
      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw FriendsAPIError.networkError(underlying: "Invalid response type")
      }

      switch httpResponse.statusCode {
      case 200...299:
        break

      case 401:
        throw FriendsAPIError.unauthorized

      default:
        if let rpcError = try? JSONDecoder().decode(RPCErrorResponse.self, from: data),
          let message = rpcError.message,
          !message.isEmpty
        {
          throw FriendsAPIError.networkError(
            underlying: "RPC \(functionName) failed (\(httpResponse.statusCode)): \(message)")
        }
        throw FriendsAPIError.httpError(statusCode: httpResponse.statusCode)
      }

      do {
        return try JSONDecoder().decode(T.self, from: data)
      } catch {
        throw FriendsAPIError.decodingError(underlying: error.localizedDescription)
      }
    } catch let error as FriendsAPIError {
      throw error
    } catch {
      throw FriendsAPIError.transportError(error)
    }
  }

  // MARK: - Helpers

  private static func sortFriends(_ friends: [FriendWithShift]) -> [FriendWithShift] {
    friends.sorted { lhs, rhs in
      let priorityOrder: [FriendShiftStatus?] = [.active, .upcoming, .past, nil]
      let lhsPriority = priorityOrder.firstIndex(where: { $0 == lhs.status }) ?? 4
      let rhsPriority = priorityOrder.firstIndex(where: { $0 == rhs.status }) ?? 4

      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      guard let lhsDateTime = shiftDateTime(shiftDate: lhs.shiftDate, time: lhs.startTime),
        let rhsDateTime = shiftDateTime(shiftDate: rhs.shiftDate, time: rhs.startTime)
      else {
        return lhs.shiftDate != nil
      }

      if lhs.status == .upcoming {
        return lhsDateTime < rhsDateTime
      }
      if lhs.status == .past {
        return lhsDateTime > rhsDateTime
      }

      return false
    }
  }

  private static func makeInitials(from name: String) -> String {
    let words = name.split(separator: " ")
    if words.count >= 2 {
      let first = words[0].prefix(1).uppercased()
      let second = words[1].prefix(1).uppercased()
      return first + second
    }
    return String(name.prefix(2).uppercased())
  }

  private static func formattedUsername(_ username: String?) -> String? {
    guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines),
      !username.isEmpty
    else {
      return nil
    }

    return username.hasPrefix("@") ? username : "@\(username)"
  }

  private static func shiftDateTime(shiftDate: String?, time: String?) -> Date? {
    guard let shiftDate, let time else { return nil }
    let dateParts = shiftDate.split(separator: "-").compactMap { Int($0) }
    let timeParts = time.split(separator: ":").compactMap { Int($0) }
    guard dateParts.count == 3, timeParts.count >= 2 else { return nil }

    var components = DateComponents()
    components.year = dateParts[0]
    components.month = dateParts[1]
    components.day = dateParts[2]
    components.hour = timeParts[0] == 24 ? 0 : timeParts[0]
    components.minute = timeParts[1]

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    guard var date = calendar.date(from: components) else { return nil }
    if timeParts[0] == 24 {
      date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    return date
  }
}

#if os(iOS)

  struct ShareRecipient: Identifiable, Equatable {
    let id: String
    let displayName: String
    let avatarURL: URL?
    let statusText: String?
    let canSeeOwnerEarnings: Bool
  }

  struct ShareRecipientThreadSummary: Equatable, Sendable {
    let counterpartUserId: String
    let timestamp: Date
    let hasUnread: Bool
  }

  enum ShareRecipientFeedOrdering {
    static func sortedRecipients(
      _ recipients: [ShareRecipient],
      threads: [ShareRecipientThreadSummary],
      shiftPreviews: [String: SharingComputedPreview]
    ) -> [ShareRecipient] {
      let threadDescriptorsByUserId = threads.reduce(into: [String: ShareRecipientThreadSummary]())
      { result, thread in
        if let existing = result[thread.counterpartUserId] {
          if thread.timestamp > existing.timestamp {
            result[thread.counterpartUserId] = thread
          } else if thread.timestamp == existing.timestamp, thread.hasUnread, !existing.hasUnread {
            result[thread.counterpartUserId] = thread
          }
        } else {
          result[thread.counterpartUserId] = thread
        }
      }

      return recipients.sorted { lhs, rhs in
        let lhsThread = threadDescriptorsByUserId[lhs.id]
        let rhsThread = threadDescriptorsByUserId[rhs.id]

        switch (lhsThread, rhsThread) {
        case (let lhsThread?, let rhsThread?):
          if lhsThread.timestamp != rhsThread.timestamp {
            return lhsThread.timestamp > rhsThread.timestamp
          }
          if lhsThread.hasUnread != rhsThread.hasUnread {
            return lhsThread.hasUnread
          }

        case (.some, .none):
          return true

        case (.none, .some):
          return false

        case (.none, .none):
          break
        }

        return compareShiftFallback(
          lhs: lhs,
          rhs: rhs,
          lhsPreview: shiftPreviews[lhs.id],
          rhsPreview: shiftPreviews[rhs.id]
        )
      }
    }

    private static func compareShiftFallback(
      lhs: ShareRecipient,
      rhs: ShareRecipient,
      lhsPreview: SharingComputedPreview?,
      rhsPreview: SharingComputedPreview?
    ) -> Bool {
      let lhsPriority = shiftStatusPriority(lhsPreview?.status)
      let rhsPriority = shiftStatusPriority(rhsPreview?.status)

      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      guard
        let lhsDateTime = shiftDateTime(
          shiftDate: lhsPreview?.shift?.shiftDate,
          time: lhsPreview?.shift?.startTime
        ),
        let rhsDateTime = shiftDateTime(
          shiftDate: rhsPreview?.shift?.shiftDate,
          time: rhsPreview?.shift?.startTime
        )
      else {
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }

      switch lhsPreview?.status {
      case .upcoming:
        if lhsDateTime != rhsDateTime {
          return lhsDateTime < rhsDateTime
        }

      case .past:
        if lhsDateTime != rhsDateTime {
          return lhsDateTime > rhsDateTime
        }

      default:
        break
      }

      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func shiftStatusPriority(_ status: SharingPreviewStatus?) -> Int {
      switch status {
      case .active: return 0
      case .upcoming: return 1
      case .past: return 2
      case .none: return 3
      }
    }

    private static func shiftDateTime(shiftDate: String?, time: String?) -> Date? {
      guard let shiftDate, let time else { return nil }
      let dateParts = shiftDate.split(separator: "-").compactMap { Int($0) }
      let timeParts = time.split(separator: ":").compactMap { Int($0) }
      guard dateParts.count == 3, timeParts.count >= 2 else { return nil }

      var components = DateComponents()
      components.calendar = Calendar(identifier: .gregorian)
      components.year = dateParts[0]
      components.month = dateParts[1]
      components.day = dateParts[2]
      components.hour = timeParts[0]
      components.minute = timeParts[1]
      components.second = 0
      return components.calendar?.date(from: components)
    }
  }

  enum SiriMessageRecipientMatcher {
    static func matches(
      for spokenName: String?,
      in recipients: [ShareRecipient]
    ) -> [ShareRecipient] {
      let query = normalizedSearchText(spokenName)
      guard !query.isEmpty else { return [] }

      let scoredRecipients = recipients.compactMap {
        recipient -> (recipient: ShareRecipient, score: Int)? in
        let fields = searchableFields(for: recipient)
        let recipientScore = fields.reduce(0) { partial, field in
          max(partial, Self.score(query: query, candidate: normalizedSearchText(field)))
        }
        guard recipientScore > 0 else { return nil }
        return (recipient, recipientScore)
      }

      let bestScore = scoredRecipients.map { $0.score }.max() ?? 0
      return
        scoredRecipients
        .filter { $0.score == bestScore }
        .sorted {
          $0.recipient.displayName.localizedCaseInsensitiveCompare($1.recipient.displayName)
            == .orderedAscending
        }
        .map { $0.recipient }
    }

    private static func searchableFields(for recipient: ShareRecipient) -> [String] {
      var fields = [recipient.displayName]

      if let statusText = recipient.statusText {
        fields.append(statusText)
      }

      return fields
    }

    private static func score(query: String, candidate: String) -> Int {
      guard !candidate.isEmpty else { return 0 }
      if candidate == query { return 100 }
      if candidate.hasPrefix(query) { return 90 }
      if candidate.split(separator: " ").contains(where: { $0 == query }) { return 80 }
      if candidate.contains(query) { return 70 }

      let queryTokens = Set(query.split(separator: " "))
      let candidateTokens = Set(candidate.split(separator: " "))
      guard !queryTokens.isEmpty, queryTokens.isSubset(of: candidateTokens) else {
        return 0
      }

      return 60
    }

    private static func normalizedSearchText(_ value: String?) -> String {
      guard let value else { return "" }

      let folded =
        value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "@", with: " ")

      let scalars = folded.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
      }

      return String(scalars)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
  }

  enum ShareExtensionMessagingClient {
    private static let storageBucket = "message-attachments"
    private static let storageBaseURL = URL(string: "https://api.tidex.no/storage/v1/object")
    private static let maxUploadBytes = 1_500_000

    static func fetchRecipients() async throws -> [ShareRecipient] {
      guard let accessToken = SharedKeychainStorage.getValidAccessToken() else {
        throw FriendsAPIError.noAccessToken
      }

      let now = Date()
      let startDate = SharingComputeCore.isoDateString(
        Calendar.gregorianCurrent.date(byAdding: .day, value: -30, to: now) ?? now)
      let endDate = SharingComputeCore.isoDateString(
        Calendar.gregorianCurrent.date(byAdding: .day, value: 30, to: now) ?? now)

      async let friendsTask = fetchFriends(
        accessToken: accessToken,
        startDate: startDate,
        endDate: endDate
      )
      async let threadsTask = fetchThreadSummaries(accessToken: accessToken)

      let response = try await friendsTask
      let threads = (try? await threadsTask) ?? []
      let recipients = response.friends
        .filter(\.isMessageable)
        .map(\.shareRecipient)
      let shiftPreviews = makeShiftPreviews(
        from: response.previewPayloads,
        startDate: startDate,
        endDate: endDate,
        now: now
      )

      return ShareRecipientFeedOrdering.sortedRecipients(
        recipients,
        threads: threads,
        shiftPreviews: shiftPreviews
      )
    }

    static func sendTextMessage(
      to recipientUserId: String,
      message: String
    ) async throws {
      guard let accessToken = SharedKeychainStorage.getValidAccessToken() else {
        throw FriendsAPIError.noAccessToken
      }

      let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedMessage.isEmpty else {
        throw FriendsAPIError.networkError(underlying: "Message content is empty")
      }

      let thread = try await getOrCreateDirectThread(
        otherUserId: recipientUserId,
        accessToken: accessToken
      )
      let payload: [String: Any] = [
        "p_thread_id": thread.threadId,
        "p_client_id": UUID().uuidString.lowercased(),
        "p_body": trimmedMessage,
        "p_reply_to_message_id": NSNull(),
        "p_attachments": [],
        "p_metadata": [:],
      ]

      _ =
        try await FriendsAPIClient.callRPC(
          functionName: "send_message",
          body: payload,
          accessToken: accessToken,
          expectsSingleObject: true
        ) as ShareMessageAck
    }

    static func sendSharedImage(
      to recipientUserId: String,
      message: String,
      imageData: Data
    ) async throws {
      guard let accessToken = SharedKeychainStorage.getValidAccessToken() else {
        throw FriendsAPIError.noAccessToken
      }

      let senderUserId = try normalizedUserId(from: accessToken)
      let thread = try await getOrCreateDirectThread(
        otherUserId: recipientUserId,
        accessToken: accessToken
      )
      let preparedImage = try prepareImage(from: imageData)
      let attachment = try await uploadImageAttachment(
        preparedImage,
        threadId: thread.threadId,
        senderUserId: senderUserId,
        accessToken: accessToken
      )

      let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
      let payload: [String: Any] = [
        "p_thread_id": thread.threadId,
        "p_client_id": UUID().uuidString.lowercased(),
        "p_body": trimmedMessage.isEmpty ? NSNull() : trimmedMessage,
        "p_reply_to_message_id": NSNull(),
        "p_attachments": [
          [
            "attachment_id": attachment.attachmentId,
            "storage_path": attachment.storagePath,
            "mime_type": attachment.mimeType,
            "byte_size": attachment.byteSize,
            "width": attachment.width as Any,
            "height": attachment.height as Any,
          ]
        ],
      ]

      _ =
        try await FriendsAPIClient.callRPC(
          functionName: "send_message",
          body: payload,
          accessToken: accessToken,
          expectsSingleObject: true
        ) as ShareMessageAck
    }

    private static func getOrCreateDirectThread(
      otherUserId: String,
      accessToken: String
    ) async throws -> ShareThreadRow {
      try await FriendsAPIClient.callRPC(
        functionName: "get_or_create_direct_thread",
        body: ["p_other_user_id": otherUserId],
        accessToken: accessToken,
        expectsSingleObject: true
      )
    }

    private static func fetchFriends(
      accessToken: String,
      startDate: String,
      endDate: String
    ) async throws -> ShareFriendsResponse {
      try await FriendsAPIClient.callRPC(
        functionName: "get_friends_tab_bootstrap",
        body: [
          "p_preview_start_date": startDate,
          "p_preview_end_date": endDate,
        ],
        accessToken: accessToken,
        expectsSingleObject: true
      )
    }

    private static func fetchThreadSummaries(accessToken: String) async throws
      -> [ShareRecipientThreadSummary]
    {
      let rows: [ShareThreadSummaryRow] = try await FriendsAPIClient.callRPC(
        functionName: "list_my_threads",
        body: [
          "p_limit": 100
        ],
        accessToken: accessToken,
        expectsSingleObject: false
      )

      return rows.compactMap(\.shareRecipientThreadSummary)
    }

    private static func makeShiftPreviews(
      from payloadRows: [SharingRPCPreviewPayloadRow],
      startDate: String,
      endDate: String,
      now: Date
    ) -> [String: SharingComputedPreview] {
      Dictionary(
        payloadRows.map { row in
          let mode: SharingRPCMode = row.showEarnings ? .visible : .hidden
          let shifts = SharingComputeCore.computeShiftsInRange(
            payload: row.payloadInput,
            startDate: startDate,
            endDate: endDate,
            mode: mode
          )
          let preview = SharingComputeCore.selectPreview(
            sharerId: row.sharerId,
            shifts: shifts,
            showEarnings: row.showEarnings,
            now: now
          )
          return (row.sharerId, preview)
        },
        uniquingKeysWith: { _, last in last }
      )
    }

    private static func uploadImageAttachment(
      _ image: PreparedSharedImage,
      threadId: String,
      senderUserId: String,
      accessToken: String
    ) async throws -> ShareOutgoingAttachment {
      guard let storageBaseURL else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorInvalidStorageBaseUrl))
      }

      let path = "\(threadId)/\(senderUserId)/\(image.id).\(image.fileExtension)"
      let uploadURL =
        storageBaseURL
        .appendingPathComponent(storageBucket)
        .appendingPathComponent(path)

      var request = URLRequest(url: uploadURL)
      request.httpMethod = "POST"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue(FriendsAPIClient.supabaseAnonKey, forHTTPHeaderField: "apikey")
      request.setValue(image.mimeType, forHTTPHeaderField: "Content-Type")
      request.setValue("false", forHTTPHeaderField: "x-upsert")

      do {
        let (_, response) = try await FriendsAPIClient.urlSession.upload(
          for: request, from: image.data)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw FriendsAPIError.networkError(
            underlying: String(localized: .shareErrorInvalidStorageResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
          throw FriendsAPIError.httpError(statusCode: httpResponse.statusCode)
        }
      } catch let error as FriendsAPIError {
        throw error
      } catch {
        throw FriendsAPIError.transportError(error)
      }

      return ShareOutgoingAttachment(
        attachmentId: image.id,
        storagePath: path,
        mimeType: image.mimeType,
        byteSize: Int64(image.data.count),
        width: image.width,
        height: image.height
      )
    }

    private static func normalizedUserId(from accessToken: String) throws -> String {
      let components = accessToken.split(separator: ".")
      guard components.count >= 2 else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorInvalidAccessToken))
      }

      var payload = String(components[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

      let remainder = payload.count % 4
      if remainder != 0 {
        payload += String(repeating: "=", count: 4 - remainder)
      }

      guard let payloadData = Data(base64Encoded: payload) else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorInvalidTokenPayload))
      }

      let jsonObject = try JSONSerialization.jsonObject(with: payloadData)
      guard
        let dictionary = jsonObject as? [String: Any],
        let subject = dictionary["sub"] as? String,
        !subject.isEmpty
      else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorMissingTokenSubject))
      }

      return subject.lowercased()
    }

    private static func prepareImage(from data: Data) throws -> PreparedSharedImage {
      guard let originalImage = UIImage(data: data) else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorUnableToReadImage))
      }

      let resizedImage = resizeImageIfNeeded(originalImage)
      let compressedData = try makeJPEGData(from: resizedImage)

      return PreparedSharedImage(
        id: UUID().uuidString.lowercased(),
        data: compressedData,
        mimeType: "image/jpeg",
        fileExtension: "jpg",
        width: Int(resizedImage.size.width.rounded()),
        height: Int(resizedImage.size.height.rounded())
      )
    }

    private static func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
      let maxDimension: CGFloat = 1_568
      let maxSide = max(image.size.width, image.size.height)
      guard maxSide > maxDimension else { return image }

      let scale = maxDimension / maxSide
      let targetSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
      )

      let format = UIGraphicsImageRendererFormat.default()
      format.scale = 1
      format.opaque = false

      let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
      return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
      }
    }

    private static func makeJPEGData(from image: UIImage) throws -> Data {
      let qualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52]

      for quality in qualities {
        if let data = image.jpegData(compressionQuality: quality), data.count <= maxUploadBytes {
          return data
        }
      }

      guard let fallbackData = image.jpegData(compressionQuality: 0.45) else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorUnableToEncodeImage))
      }

      guard fallbackData.count <= maxUploadBytes else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorImageTooLarge))
      }

      return fallbackData
    }

    private struct PreparedSharedImage {
      let id: String
      let data: Data
      let mimeType: String
      let fileExtension: String
      let width: Int?
      let height: Int?
    }

    private struct ShareThreadRow: Decodable {
      let threadId: String

      private enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
      }
    }

    private struct ShareMessageAck: Decodable {
      let id: String
    }

    private struct ShareOutgoingAttachment {
      let attachmentId: String
      let storagePath: String
      let mimeType: String
      let byteSize: Int64
      let width: Int?
      let height: Int?
    }

    private struct ShareFriendsResponse: Decodable {
      let friends: [ShareFriendRow]
      let previewPayloads: [SharingRPCPreviewPayloadRow]

      private enum CodingKeys: String, CodingKey {
        case friends
        case previewPayloads
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friends = try container.decodeIfPresent([ShareFriendRow].self, forKey: .friends) ?? []
        previewPayloads =
          try container.decodeIfPresent(
            [SharingRPCPreviewPayloadRow].self, forKey: .previewPayloads)
          ?? []
      }
    }

    private struct ShareThreadSummaryRow: Decodable {
      let kind: String
      let counterpartUserId: String?
      let lastMessageAt: String?
      let unreadCount: Int
      let createdAt: String

      var shareRecipientThreadSummary: ShareRecipientThreadSummary? {
        guard kind == "direct",
          let counterpartUserId,
          let timestamp = Self.parseTimestamp(lastMessageAt) ?? Self.parseTimestamp(createdAt)
        else {
          return nil
        }

        return ShareRecipientThreadSummary(
          counterpartUserId: counterpartUserId,
          timestamp: timestamp,
          hasUnread: unreadCount > 0
        )
      }

      private enum CodingKeys: String, CodingKey {
        case kind
        case counterpartUserId = "counterpart_user_id"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
        case createdAt = "created_at"
      }

      private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601Timestamp.date(from: value)
      }
    }

    private struct ShareFriendRow: Decodable {
      let id: String
      let email: String?
      let phone: String?
      let firstName: String?
      let profilePictureUrl: String?
      let oauthAvatarUrl: String?
      let sharesWithMe: ShareDirection?
      let iShareWith: ShareDirection?

      var isMessageable: Bool {
        sharesWithMe != nil || iShareWith != nil
      }

      var shareRecipient: ShareRecipient {
        ShareRecipient(
          id: id,
          displayName: displayName,
          avatarURL: effectiveAvatarURL,
          statusText: contactInfo,
          canSeeOwnerEarnings: iShareWith?.showEarningsToThem ?? false
        )
      }

      private var displayName: String {
        if let firstName, !firstName.isEmpty {
          return firstName
        }
        if let email, !email.isEmpty {
          return email.components(separatedBy: "@").first ?? email
        }
        if let phone, !phone.isEmpty {
          return phone
        }
        return String(localized: .shareRecipientUnknown)
      }

      private var contactInfo: String? {
        if let firstName, !firstName.isEmpty {
          if let email, !email.isEmpty {
            return email
          }
          if let phone, !phone.isEmpty {
            return phone
          }
        }

        if let email, !email.isEmpty, let phone, !phone.isEmpty {
          return phone
        }

        return nil
      }

      private var effectiveAvatarURL: URL? {
        guard let urlString = profilePictureUrl ?? oauthAvatarUrl, !urlString.isEmpty else {
          return nil
        }

        return URL(string: urlString)
      }
    }

    private struct ShareDirection: Decodable {
      let showEarningsToThem: Bool?

      private enum CodingKeys: String, CodingKey {
        case showEarningsToThem
      }
    }
  }

#endif
// swiftlint:enable file_length function_body_length cyclomatic_complexity
