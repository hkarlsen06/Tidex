import XCTest

@testable import Tidex

/// Siri may only read a friend's shifts while they share them, and their pay only while they
/// share earnings. The local cache can hold more than that, for example after a friend stops.
final class FriendDayScheduleTests: XCTestCase {
  private let cached = [
    TestFixtures.computedShift(
      id: "late", shiftDate: "2026-11-06", startTime: "22:00", endTime: "06:00", gross: 1_800),
    TestFixtures.computedShift(
      id: "early", shiftDate: "2026-11-06", startTime: "08:00", endTime: "12:00", gross: 800),
    TestFixtures.computedShift(
      id: "other-day", shiftDate: "2026-11-07", startTime: "08:00", endTime: "16:00", gross: 1_600),
  ]

  private func friend(_ id: String, showEarnings: Bool) -> SharedUser {
    SharedUser(
      id: id, email: nil, phone: nil, firstName: "Kari", profilePictureUrl: nil,
      oauthAvatarUrl: nil, sharedAt: "2026-01-01", showEarnings: showEarnings, hidden: false)
  }

  private func schedule(sharers: [SharedUser], currency: String? = "kr") -> FriendDaySchedule? {
    FriendDaySchedule.make(
      friendId: "kari", sharers: sharers, cachedShifts: cached, day: "2026-11-06",
      earningsCurrency: currency)
  }

  func testAFriendWhoDoesNotShareGetsNoAnswerFromCachedShifts() {
    XCTAssertNil(schedule(sharers: []))
    XCTAssertNil(schedule(sharers: [friend("ola", showEarnings: true)]))
  }

  func testHiddenEarningsAreNeverRead() throws {
    let day = try XCTUnwrap(schedule(sharers: [friend("KARI", showEarnings: false)]))

    XCTAssertEqual(day.shifts.count, 2)
    XCTAssertEqual(day.shifts.compactMap(\.gross), [])
    XCTAssertNil(day.currency)
  }

  func testEarningsNeedAKnownCurrency() throws {
    let day = try XCTUnwrap(schedule(sharers: [friend("kari", showEarnings: true)], currency: nil))

    XCTAssertEqual(day.shifts.compactMap(\.gross), [])
  }

  func testASharingFriendsDayInOrderWithPay() throws {
    let day = try XCTUnwrap(schedule(sharers: [friend("kari", showEarnings: true)]))

    XCTAssertEqual(day.friendName, "Kari")
    XCTAssertEqual(day.shifts.map(\.gross), [800, 1_800])
    XCTAssertEqual(day.shifts.last?.interval.end, Date.fromDateAndTime("2026-11-07", time: "06:00"))
    XCTAssertEqual(day.currency, "kr")
  }
}
