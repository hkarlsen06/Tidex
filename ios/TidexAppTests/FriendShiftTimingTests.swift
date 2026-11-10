import XCTest

@testable import Tidex

final class FriendShiftTimingTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }

  func testOvernightShiftEndsOnNextDay() throws {
    let timing = try XCTUnwrap(FriendShiftTiming(shift: makeShift(start: "22:00", end: "06:00")))

    XCTAssertEqual(timing.end.timeIntervalSince(timing.start), 8 * 3_600)
    XCTAssertEqual(calendar.component(.hour, from: timing.end), 6)
  }

  func testStatusAndProgressAcrossTheShift() throws {
    let timing = try XCTUnwrap(FriendShiftTiming(shift: makeShift(start: "08:00", end: "16:00")))

    let before = timing.start.addingTimeInterval(-60)
    let midway = timing.start.addingTimeInterval(4 * 3_600)
    let after = timing.end.addingTimeInterval(60)

    XCTAssertEqual(timing.status(at: before), .upcoming)
    XCTAssertEqual(timing.status(at: timing.start), .active)
    XCTAssertEqual(timing.status(at: midway), .active)
    XCTAssertEqual(timing.status(at: timing.end), .past)
    XCTAssertEqual(timing.status(at: after), .past)

    XCTAssertEqual(timing.progress(at: before), 0)
    XCTAssertEqual(timing.progress(at: midway), 0.5, accuracy: 0.0001)
    XCTAssertEqual(timing.progress(at: after), 1)
  }

  func testMalformedTimesProduceNoTiming() {
    XCTAssertNil(FriendShiftTiming(shift: makeShift(start: "8", end: "16:00")))
    XCTAssertNil(FriendShiftTiming(shift: makeShift(date: "not-a-date")))
  }

  func testLondonShiftIsFiveAndAHalfHoursAwayForOsloViewerAtHalfPastMidnight() throws {
    let shift = makeShift(date: "2026-11-10", start: "05:00", end: "13:00", zone: "Europe/London")
    let timing = try XCTUnwrap(FriendShiftTiming(shift: shift))
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T23:30:00Z"))
    XCTAssertEqual(timing.start.timeIntervalSince(now), 5.5 * 3_600)
    XCTAssertEqual(timing.status(at: now), .upcoming)
    let interval = try XCTUnwrap(
      SharedShiftInterval(
        date: shift.shift_date, startTime: shift.start_time,
        endTime: shift.end_time, timeZoneIdentifier: shift.ownerTimeZone))
    let oslo = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
    XCTAssertEqual(clockComponents(interval.start, in: oslo), DateComponents(hour: 6, minute: 0))
    XCTAssertEqual(
      interval.clock(interval.start, in: oslo, locale: Locale(identifier: "en_GB")), "06:00")
    XCTAssertEqual(interval.dateString(in: oslo), "2026-11-10")
  }

  func testViewerEastAndWestSeeTheSameInstantAndCorrectDate() throws {
    let interval = try XCTUnwrap(
      SharedShiftInterval(
        date: "2026-11-10", startTime: "23:30", endTime: "07:30",
        timeZoneIdentifier: "Europe/London"))
    let oslo = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
    let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    XCTAssertEqual(interval.dateString(in: oslo), "2026-11-11")
    XCTAssertEqual(interval.dateString(in: newYork), "2026-11-10")
    XCTAssertEqual(interval.start, ISO8601DateFormatter().date(from: "2026-11-10T23:30:00Z"))
  }

  func testOvernightEndUsesSourceCalendarAcrossBothDSTChanges() throws {
    for (date, hours) in [("2026-10-24", 9.0), ("2026-03-28", 7.0)] {
      let interval = try XCTUnwrap(
        SharedShiftInterval(
          date: date, startTime: "22:00", endTime: "06:00",
          timeZoneIdentifier: "Europe/London"))
      XCTAssertEqual(interval.end.timeIntervalSince(interval.start), hours * 3_600)
      XCTAssertEqual(
        clockComponents(interval.end, in: interval.timeZone), DateComponents(hour: 6, minute: 0))
      XCTAssertEqual(
        interval.clock(interval.end, in: interval.timeZone, locale: Locale(identifier: "en_GB")),
        "06:00")
      XCTAssertEqual(
        interval.timeRange(in: interval.timeZone, locale: Locale(identifier: "en_GB")),
        "22:00 – 06:00")
    }
  }

  func testOffsetComparisonUsesTheShiftDateInsteadOfTodaysOffsetOrZoneName() throws {
    let oslo = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
    for (date, hour) in [("2026-10-20", 15), ("2026-10-28", 14)] {
      let interval = try XCTUnwrap(
        SharedShiftInterval(
          date: date, startTime: "09:00", endTime: "17:00",
          timeZoneIdentifier: "America/New_York"))
      XCTAssertEqual(
        clockComponents(interval.start, in: oslo), DateComponents(hour: hour, minute: 0))
      XCTAssertTrue(interval.differs(from: oslo))
    }
    let berlin = try XCTUnwrap(
      SharedShiftInterval(
        date: "2026-11-10", startTime: "09:00", endTime: "17:00",
        timeZoneIdentifier: "Europe/Berlin"))
    XCTAssertFalse(berlin.differs(from: oslo))
  }

  func testMidnightAndMissingOrInvalidSourceZone() throws {
    let midnight = try XCTUnwrap(
      SharedShiftInterval(
        date: "2026-11-10", startTime: "22:00", endTime: "24:00",
        timeZoneIdentifier: "Europe/London"))
    XCTAssertEqual(midnight.end.timeIntervalSince(midnight.start), 2 * 3_600)
    for zone in [nil, "", "+01:00", "PST", "europe/oslo", "Invalid/Zone"] {
      XCTAssertNil(FriendShiftTiming(shift: makeShift(zone: zone)))
    }
    for (date, start, end) in [
      ("2026-02-30", "08:00", "16:00"), ("2026-11-10", "25:00", "16:00"),
      ("2026-11-10", "08:90", "16:00"), ("2026-11-10", "08:00", "24:01"),
    ] {
      XCTAssertNil(FriendShiftTiming(shift: makeShift(date: date, start: start, end: end)))
    }
  }

  @MainActor
  func testZoneCacheSeparatesViewersPrunesRemovedSharesAndClearsOnSignOut() throws {
    let suite = "FriendShiftTimingTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let cache = FriendsScheduleTimeZoneStore(defaults: defaults)
    cache.set("Europe/London", ownerId: "friend", viewerId: "viewer-a")
    cache.set("Asia/Tokyo", ownerId: "friend", viewerId: "viewer-b")
    XCTAssertEqual(cache.zone(ownerId: "friend", viewerId: "viewer-a"), "Europe/London")
    XCTAssertEqual(cache.zone(ownerId: "friend", viewerId: "viewer-b"), "Asia/Tokyo")
    cache.replace([], viewerId: "viewer-a")
    XCTAssertNil(cache.zone(ownerId: "friend", viewerId: "viewer-a"))
    XCTAssertEqual(cache.zone(ownerId: "friend", viewerId: "viewer-b"), "Asia/Tokyo")
    cache.resetForUserChange()
    XCTAssertNil(cache.zone(ownerId: "friend", viewerId: "viewer-b"))
  }

  func testPreviewSelectionUsesTheSourceZoneAndUnknownMakesNoAvailabilityClaim() throws {
    let shift = SharingComputedShift(
      id: "london", userId: "friend", jobId: nil, jobName: nil, jobColor: nil,
      shiftDate: "2026-11-10", startTime: "05:00", endTime: "13:00", customPauseWindows: nil,
      customSupplements: nil, recurringId: nil, recurringAnchorWeekday: nil,
      computed: SharingComputedShiftComputed(
        durationHours: 8, paidHours: 8, basePay: 0,
        supplementPay: 0, gross: 0, wagePeriods: [], originalWagePeriods: [],
        breakAudit: BreakAudit(
          method: .none, thresholdHours: 0, deductedHours: 0,
          source: .none, notes: [])), taxEnabled: false, taxPercentage: 0)
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-10T04:30:00Z"))
    let preview = SharingComputeCore.selectPreview(
      sharerId: "friend", shifts: [shift],
      showEarnings: false, ownerTimeZone: "Europe/London", now: now)
    XCTAssertEqual(preview.shift?.id, "london")
    XCTAssertEqual(preview.status, .upcoming)
    let unknown = SharingComputeCore.selectPreview(
      sharerId: "friend", shifts: [shift],
      showEarnings: false, ownerTimeZone: nil, now: now)
    XCTAssertNil(unknown.shift)
    XCTAssertNil(unknown.status)
  }

  func testWidgetCacheKeepsSourceZoneAndOldCacheCannotInferAnInstant() throws {
    let preview = SharerShiftPreview(
      sharerId: "friend", shift: makeShift(zone: "Europe/London"),
      status: .upcoming, showEarnings: false, currency: nil)
    let stored = try XCTUnwrap(StoredFriendShift.from(preview: preview, currencySymbol: nil))
    let decoded = try JSONDecoder().decode(
      StoredFriendShift.self, from: JSONEncoder().encode(stored))
    XCTAssertEqual(decoded.ownerTimeZone, "Europe/London")
    let oldData = Data(
      #"{"sharerId":"friend","shiftId":"shift","shiftDate":"2026-11-10","startTime":"05:00","endTime":"13:00","gross":0,"showEarnings":false,"status":"upcoming"}"#
        .utf8)
    let old = try JSONDecoder().decode(StoredFriendShift.self, from: oldData)
    XCTAssertNil(old.ownerTimeZone)
    XCTAssertNil(
      SharedShiftInterval(
        date: old.shiftDate, startTime: old.startTime,
        endTime: old.endTime, timeZoneIdentifier: old.ownerTimeZone))
  }

  private func clockComponents(_ date: Date, in zone: TimeZone) -> DateComponents {
    var calendar = self.calendar
    calendar.timeZone = zone
    return calendar.dateComponents([.hour, .minute], from: date)
  }

  private func makeShift(
    date: String = "2026-03-12",
    start: String = "08:00",
    end: String = "16:00",
    zone: String? = "UTC"
  ) -> SharedShiftData {
    SharedShiftData(
      id: "shift",
      user_id: "friend",
      job_id: nil,
      job_name: nil,
      job_color: nil,
      shift_date: date,
      start_time: start,
      end_time: end,
      computed: SharedShiftComputed(
        id: "shift",
        durationHours: 8,
        paidHours: 8,
        basePay: 1_000,
        supplementPay: 0,
        gross: 1_000,
        breakAudit: SharedBreakAudit(
          method: .none,
          thresholdHours: 0,
          deductedHours: 0,
          source: .none,
          appliedPauseWindows: nil,
          notes: []
        )
      ),
      tax_enabled: nil,
      tax_percentage: nil,
      custom_pause_windows: nil,
      custom_supplements: nil,
      recurring_id: nil,
      recurring_anchor_weekday: nil,
      ownerTimeZone: zone
    )
  }
}
