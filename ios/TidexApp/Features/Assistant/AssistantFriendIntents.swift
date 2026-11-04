import AppIntents
import Foundation

/// What Siri may say about a friend's shifts on one day.
struct FriendDaySchedule: Equatable {
  struct Shift: Equatable {
    let interval: DateInterval
    /// Nil unless the friend shares earnings and their currency is known.
    let gross: Double?
  }

  let friendName: String
  let shifts: [Shift]
  let currency: String?

  /// `sharers` are the friends who share shifts with the user, without hidden or blocked ones.
  /// Anyone else gets nil, whatever the cache holds.
  static func make(
    friendId: String,
    sharers: [SharedUser],
    cachedShifts: [ShiftWithComputations],
    day: String,
    earningsCurrency: String?
  ) -> Self? {
    guard let sharer = sharers.first(where: { $0.id.lowercased() == friendId.lowercased() }) else {
      return nil
    }
    let currency = sharer.showEarnings ? earningsCurrency : nil
    let shifts = cachedShifts.filter { $0.shiftDate == day }.compactMap { shift -> Shift? in
      guard
        let start = Date.fromDateAndTime(shift.shiftDate, time: shift.startTime),
        let end = Date.shiftEndDate(
          shiftDate: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)
      else {
        return nil
      }
      return Shift(
        interval: DateInterval(start: start, end: end),
        gross: currency == nil ? nil : shift.grossPay)
    }
    return Self(
      friendName: sharer.displayName,
      shifts: shifts.sorted { $0.interval.start < $1.interval.start },
      currency: currency)
  }
}

struct FriendScheduleIntent: AppIntent {
  static let title: LocalizedStringResource = "assistant.friendSchedule.title"
  static let description = IntentDescription("assistant.friendSchedule.description")

  @Parameter(title: "assistant.friend.type", description: "assistant.friendSchedule.friend.description")
  var friend: FriendEntity

  @Parameter(title: "assistant.addShift.date", description: "assistant.friendSchedule.date.description", kind: .date)
  var date: Date?

  @MainActor
  func perform() throws -> some IntentResult & ProvidesDialog {
    let userId = try AssistantAccess.current.requireUserId()
    let day = date ?? Date()
    let month = day.yearMonth()
    let repository = SharedShiftsRepository.shared
    guard
      let schedule = FriendDaySchedule.make(
        friendId: friend.id,
        sharers: repository.getSharers(for: userId),
        cachedShifts: repository.getSharedShifts(
          ownerId: friend.id, viewerId: userId, year: month.year, month: month.month),
        day: day.toISODateString(),
        earningsCurrency: repository.getShiftPreviews(for: userId)[friend.id]?.currency)
    else {
      throw AssistantError.friendNotSharing
    }
    let dayText = day.formatted(.dateTime.weekday(.wide).day().month(.wide))

    guard !schedule.shifts.isEmpty else {
      let loaded = repository.hasFetchRecord(
        ownerId: friend.id, viewerId: userId, year: month.year, month: month.month)
      return .result(
        dialog: IntentDialog(
          loaded
            ? .assistantFriendScheduleNone(schedule.friendName, dayText)
            : .assistantFriendScheduleNotLoaded(schedule.friendName)))
    }
    let shiftTexts = schedule.shifts.map { shift in
      let start = shift.interval.start.formatted(date: .omitted, time: .shortened)
      let end = shift.interval.end.formatted(date: .omitted, time: .shortened)
      guard let gross = shift.gross, let currency = schedule.currency else {
        return String(localized: .assistantFriendScheduleShift(start, end))
      }
      return String(
        localized: .assistantFriendScheduleShiftEarnings(
          start, end, CurrencyConfig.format(gross, currency: currency)))
    }
    return .result(
      dialog: IntentDialog(
        .assistantFriendScheduleWorks(
          schedule.friendName, dayText, shiftTexts.formatted(.list(type: .and)))))
  }
}
