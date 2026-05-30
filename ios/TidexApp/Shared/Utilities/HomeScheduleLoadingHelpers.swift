import Foundation

struct ShiftChangeAffectedMonth: Hashable, Comparable {
  let year: Int
  let month: Int

  init?(year: Int, month: Int) {
    guard year > 0, (1...12).contains(month) else { return nil }
    self.year = year
    self.month = month
  }

  init?(dateISO: String) {
    let parts = dateISO.split(separator: "-")
    guard parts.count >= 2,
      let year = Int(parts[0]),
      let month = Int(parts[1])
    else {
      return nil
    }

    self.init(year: year, month: month)
  }

  init(date: Date, timeZone: TimeZone = Date.localTimeZone) {
    let yearMonth = date.yearMonth(in: timeZone)
    self.year = yearMonth.year
    self.month = yearMonth.month
  }

  var cacheKey: String {
    String(format: "%04d-%02d", year, month)
  }

  static func < (lhs: ShiftChangeAffectedMonth, rhs: ShiftChangeAffectedMonth) -> Bool {
    if lhs.year == rhs.year {
      return lhs.month < rhs.month
    }
    return lhs.year < rhs.year
  }
}

struct ShiftChangeNotificationPayload: Equatable {
  static let payloadUserInfoKey = "com.tidex.shiftChange.payload"
  static let affectedMonthsUserInfoKey = "affectedMonths"
  static let affectedDatesUserInfoKey = "affectedDates"
  static let requiresFullReloadUserInfoKey = "requiresFullReload"

  let affectedMonths: Set<ShiftChangeAffectedMonth>
  let requiresFullReload: Bool

  init(
    affectedMonths: Set<ShiftChangeAffectedMonth> = [],
    requiresFullReload: Bool = false
  ) {
    self.affectedMonths = affectedMonths
    self.requiresFullReload = requiresFullReload || affectedMonths.isEmpty
  }

  var canUseTargetedInvalidation: Bool {
    !requiresFullReload && !affectedMonths.isEmpty
  }

  static var fullReload: ShiftChangeNotificationPayload {
    ShiftChangeNotificationPayload(requiresFullReload: true)
  }

  static func userInfo(
    affectedMonths: Set<ShiftChangeAffectedMonth> = [],
    requiresFullReload: Bool = false
  ) -> [AnyHashable: Any] {
    let payload = ShiftChangeNotificationPayload(
      affectedMonths: affectedMonths,
      requiresFullReload: requiresFullReload
    )

    return [
      payloadUserInfoKey: payload,
      affectedMonthsUserInfoKey: affectedMonths.map {
        ["year": $0.year, "month": $0.month]
      },
      requiresFullReloadUserInfoKey: payload.requiresFullReload,
    ]
  }

  static func parse(from notification: Notification) -> ShiftChangeNotificationPayload {
    guard let userInfo = notification.userInfo else {
      return .fullReload
    }

    if let payload = userInfo[payloadUserInfoKey] as? ShiftChangeNotificationPayload {
      return payload
    }

    let requiresFullReload = userInfo[requiresFullReloadUserInfoKey] as? Bool ?? false
    let affectedMonths = parseAffectedMonths(from: userInfo[affectedMonthsUserInfoKey])
      .union(parseAffectedMonths(from: userInfo[affectedDatesUserInfoKey]))

    return ShiftChangeNotificationPayload(
      affectedMonths: affectedMonths,
      requiresFullReload: requiresFullReload
    )
  }

  private static func parseAffectedMonths(from value: Any?) -> Set<ShiftChangeAffectedMonth> {
    guard let value else { return [] }

    if let month = parseAffectedMonth(from: value) {
      return [month]
    }

    guard let values = value as? [Any] else { return [] }
    return Set(values.compactMap(parseAffectedMonth))
  }

  private static func parseAffectedMonth(from value: Any) -> ShiftChangeAffectedMonth? {
    if let month = value as? ShiftChangeAffectedMonth {
      return month
    }

    if let value = value as? String {
      return ShiftChangeAffectedMonth(dateISO: value)
    }

    if let value = value as? [String: Int] {
      return ShiftChangeAffectedMonth(year: value["year"] ?? 0, month: value["month"] ?? 0)
    }

    if let value = value as? [String: Any] {
      return ShiftChangeAffectedMonth(
        year: intValue(value["year"]) ?? 0,
        month: intValue(value["month"]) ?? 0
      )
    }

    return nil
  }

  private static func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
      return value
    case let value as NSNumber:
      return value.intValue
    case let value as String:
      return Int(value)
    default:
      return nil
    }
  }
}

typealias ShiftChangeMonth = ShiftChangeAffectedMonth
typealias ShiftChangeContext = ShiftChangeNotificationPayload

extension ShiftChangeNotificationPayload {
  static func affecting(months: Set<ShiftChangeAffectedMonth>) -> ShiftChangeNotificationPayload {
    ShiftChangeNotificationPayload(affectedMonths: months)
  }

  static func affecting(date: Date, timeZone: TimeZone = Date.localTimeZone)
    -> ShiftChangeNotificationPayload
  {
    affecting(months: [ShiftChangeAffectedMonth(date: date, timeZone: timeZone)])
  }

  static func affecting(isoDate: String) -> ShiftChangeNotificationPayload {
    guard let month = ShiftChangeAffectedMonth(dateISO: isoDate) else {
      return .fullReload
    }
    return affecting(months: [month])
  }

  static func affecting<S: Sequence>(isoDates: S) -> ShiftChangeNotificationPayload
  where S.Element == String {
    affecting(months: Set(isoDates.compactMap(ShiftChangeAffectedMonth.init(dateISO:))))
  }

  static func affecting(
    dateRangeStart: Date,
    end: Date,
    timeZone: TimeZone = Date.localTimeZone
  ) -> ShiftChangeNotificationPayload {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let orderedStart = min(dateRangeStart, end)
    let orderedEnd = max(dateRangeStart, end)
    let startComponents = calendar.dateComponents([.year, .month], from: orderedStart)
    let endComponents = calendar.dateComponents([.year, .month], from: orderedEnd)

    guard
      let startMonth = calendar.date(
        from: DateComponents(
          year: startComponents.year,
          month: startComponents.month,
          day: 1
        )),
      let endMonth = calendar.date(
        from: DateComponents(
          year: endComponents.year,
          month: endComponents.month,
          day: 1
        ))
    else {
      return .fullReload
    }

    var months: Set<ShiftChangeAffectedMonth> = []
    var cursor = startMonth

    while cursor <= endMonth {
      months.insert(ShiftChangeAffectedMonth(date: cursor, timeZone: timeZone))
      guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
        return .fullReload
      }
      cursor = next
    }

    return affecting(months: months)
  }

}

extension ShiftChangeNotificationPayload {
  static func affecting(isoDate: String?) -> ShiftChangeNotificationPayload {
    guard let isoDate,
      let affectedMonth = ShiftChangeAffectedMonth(dateISO: isoDate)
    else {
      return .fullReload
    }

    return ShiftChangeNotificationPayload(affectedMonths: [affectedMonth])
  }

  static func affecting(isoDates: [String?]) -> ShiftChangeNotificationPayload {
    let affectedMonths = Set(
      isoDates.compactMap { isoDate -> ShiftChangeAffectedMonth? in
        guard let isoDate else { return nil }
        return ShiftChangeAffectedMonth(dateISO: isoDate)
      })

    return ShiftChangeNotificationPayload(affectedMonths: affectedMonths)
  }

  static func affecting(
    isoDateRangeStart startISO: String,
    end endISO: String
  ) -> ShiftChangeNotificationPayload {
    guard let startMonth = ShiftChangeAffectedMonth(dateISO: startISO),
      let endMonth = ShiftChangeAffectedMonth(dateISO: endISO)
    else {
      return .fullReload
    }

    return ShiftChangeNotificationPayload(
      affectedMonths: months(from: startMonth, through: endMonth)
    )
  }

  func merging(_ other: ShiftChangeNotificationPayload) -> ShiftChangeNotificationPayload {
    guard !requiresFullReload, !other.requiresFullReload else {
      return .fullReload
    }

    return ShiftChangeNotificationPayload(
      affectedMonths: affectedMonths.union(other.affectedMonths)
    )
  }

  var notificationUserInfo: [AnyHashable: Any] {
    Self.userInfo(
      affectedMonths: affectedMonths,
      requiresFullReload: requiresFullReload
    )
  }

  private static func months(
    from startMonth: ShiftChangeAffectedMonth,
    through endMonth: ShiftChangeAffectedMonth
  ) -> Set<ShiftChangeAffectedMonth> {
    let lowerBound = min(startMonth, endMonth)
    let upperBound = max(startMonth, endMonth)
    var result: Set<ShiftChangeAffectedMonth> = []
    var year = lowerBound.year
    var month = lowerBound.month

    while year < upperBound.year || (year == upperBound.year && month <= upperBound.month) {
      if let affectedMonth = ShiftChangeAffectedMonth(year: year, month: month) {
        result.insert(affectedMonth)
      }

      if month == 12 {
        year += 1
        month = 1
      } else {
        month += 1
      }
    }

    return result
  }
}

extension Notification.Name {
  /// Posted when local shift, event, or payroll-related data changes.
  static let shiftsDidChange = Notification.Name("com.tidex.shiftsDidChange")
}

extension Notification {
  var shiftChangeContext: ShiftChangeNotificationPayload {
    ShiftChangeNotificationPayload.parse(from: self)
  }
}

extension NotificationCenter {
  func postShiftsDidChange(
    object: Any? = nil,
    context: ShiftChangeContext = .fullReload
  ) {
    post(name: .shiftsDidChange, object: object, userInfo: context.notificationUserInfo)
  }
}

extension SyncCompletionSummary {
  // Jobs and wage snapshots are handled through `.workSetupDataDidChange` so sync summaries do not
  // trigger a second Home/Schedule reload for the same sync.
  private static let dashboardRelevantTables: Set<SyncTable> = [
    .userShifts,
    .events,
    .recurringShifts,
    .payrollAdjustments,
    .userSettings,
  ]

  private static let scheduleRelevantTables: Set<SyncTable> = [
    .userShifts,
    .events,
    .recurringShifts,
    .userSettings,
  ]

  private static let targetedMonthTables: Set<SyncTable> = [
    .userShifts,
    .events,
    .payrollAdjustments,
  ]

  var dashboardChangeContext: ShiftChangeContext? {
    changeContext(relevantTables: Self.dashboardRelevantTables)
  }

  var scheduleChangeContext: ShiftChangeContext? {
    changeContext(relevantTables: Self.scheduleRelevantTables)
  }

  private func changeContext(relevantTables: Set<SyncTable>) -> ShiftChangeContext? {
    let relevantChanges = localReadModelChanges.filter { relevantTables.contains($0.table) }
    guard !relevantChanges.isEmpty else { return nil }

    guard
      relevantChanges.allSatisfy({
        Self.targetedMonthTables.contains($0.table) && !$0.affectedMonths.isEmpty
      })
    else {
      return .fullReload
    }

    return .affecting(months: Set(relevantChanges.flatMap(\.affectedMonths)))
  }
}

enum HomeScheduleMonthLoadDecision: Equatable {
  case none
  case loadNow(ShiftChangeAffectedMonth)
  case deferUntilVisible(ShiftChangeAffectedMonth)
}

struct HomeScheduleMonthLoadingGate: Equatable {
  private(set) var isVisible: Bool
  private(set) var pendingMonth: ShiftChangeAffectedMonth?

  init(isVisible: Bool = true, pendingMonth: ShiftChangeAffectedMonth? = nil) {
    self.isVisible = isVisible
    self.pendingMonth = pendingMonth
  }

  mutating func setVisible(_ visible: Bool) -> HomeScheduleMonthLoadDecision {
    let wasVisible = isVisible
    isVisible = visible

    guard visible, !wasVisible, let pendingMonth else {
      return .none
    }

    self.pendingMonth = nil
    return .loadNow(pendingMonth)
  }

  mutating func monthDidChange(to month: ShiftChangeAffectedMonth) -> HomeScheduleMonthLoadDecision
  {
    requestLoad(for: month)
  }

  mutating func dataDidChange(
    payload: ShiftChangeNotificationPayload,
    currentMonth: ShiftChangeAffectedMonth
  ) -> HomeScheduleMonthLoadDecision {
    guard payload.requiresFullReload || payload.affectedMonths.contains(currentMonth) else {
      return .none
    }

    return requestLoad(for: currentMonth)
  }

  private mutating func requestLoad(
    for month: ShiftChangeAffectedMonth
  ) -> HomeScheduleMonthLoadDecision {
    guard isVisible else {
      pendingMonth = month
      return .deferUntilVisible(month)
    }

    pendingMonth = nil
    return .loadNow(month)
  }
}

enum HomeScheduleAffectedMonthResolver {
  static func dashboardDisplayedMonthDepends(
    on affectedMonths: Set<ShiftChangeAffectedMonth>,
    displayYear: Int,
    displayMonth: Int
  ) -> Bool {
    guard let displayedMonth = ShiftChangeAffectedMonth(year: displayYear, month: displayMonth)
    else {
      return true
    }

    let previousYM = Date.previousYearMonth(from: (year: displayYear, month: displayMonth))
    guard
      let previousMonth = ShiftChangeAffectedMonth(
        year: previousYM.year,
        month: previousYM.month
      )
    else {
      return true
    }

    return affectedMonths.contains(displayedMonth) || affectedMonths.contains(previousMonth)
  }

  static func scheduleDisplayMonthsAffected(
    by affectedMonths: Set<ShiftChangeAffectedMonth>
  ) -> Set<ShiftChangeAffectedMonth> {
    var displayMonths: Set<ShiftChangeAffectedMonth> = []

    for affectedMonth in affectedMonths {
      let previousYM = Date.previousYearMonth(
        from: (year: affectedMonth.year, month: affectedMonth.month)
      )
      let nextYM = nextYearMonth(from: (year: affectedMonth.year, month: affectedMonth.month))

      displayMonths.insert(affectedMonth)
      if let previousMonth = ShiftChangeAffectedMonth(
        year: previousYM.year,
        month: previousYM.month
      ) {
        displayMonths.insert(previousMonth)
      }
      if let nextMonth = ShiftChangeAffectedMonth(year: nextYM.year, month: nextYM.month) {
        displayMonths.insert(nextMonth)
      }
    }

    return displayMonths
  }

  private static func nextYearMonth(from current: (year: Int, month: Int)) -> (
    year: Int,
    month: Int
  ) {
    if current.month == 12 {
      return (year: current.year + 1, month: 1)
    }
    return (year: current.year, month: current.month + 1)
  }
}
