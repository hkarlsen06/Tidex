import XCTest

@testable import Tidex

internal final class ICSShiftParserTests: XCTestCase {
  // swiftlint:disable:next force_unwrapping
  private let oslo: TimeZone = TimeZone(identifier: "Europe/Oslo")!

  private func calendar(_ events: String) -> String {
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n\(events)END:VCALENDAR\r\n"
  }

  private func times(_ shifts: [CalendarImportShift]) -> [String] {
    shifts.map(\.id)
  }

  // MARK: - Times

  internal func testReadsTzidUtcAndFloatingTimes() {
    let ics: String = calendar(
      """
      BEGIN:VEVENT\r
      UID:1\r
      DTSTART;TZID=Europe/Oslo:20260301T080000\r
      DTEND;TZID=Europe/Oslo:20260301T160000\r
      SUMMARY:Kasse\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      UID:2\r
      DTSTART:20260302T070000Z\r
      DTEND:20260302T150000Z\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      UID:3\r
      DTSTART:20260303T090000\r
      DTEND:20260303T1700\r
      END:VEVENT\r

      """)

    let shifts: [CalendarImportShift] = ICSShiftParser.shifts(from: ics, timeZone: oslo)

    XCTAssertEqual(
      times(shifts),
      ["2026-03-01 08:00 16:00", "2026-03-02 08:00 16:00", "2026-03-03 09:00 17:00"])
    XCTAssertEqual(shifts.first?.title, "Kasse")
  }

  internal func testUtcTimesFollowSummerTime() {
    let ics: String = calendar(
      "BEGIN:VEVENT\r\nDTSTART:20260701T060000Z\r\nDTEND:20260701T140000Z\r\nEND:VEVENT\r\n")

    XCTAssertEqual(
      times(ICSShiftParser.shifts(from: ics, timeZone: oslo)), ["2026-07-01 08:00 16:00"])
  }

  internal func testVendorPrefixedTzidResolves() {
    let ics: String = calendar(
      """
      BEGIN:VEVENT\r
      DTSTART;TZID="/mozilla.org/20050126_1/America/New_York":20260301T080000\r
      DTEND;TZID="/mozilla.org/20050126_1/America/New_York":20260301T100000\r
      END:VEVENT\r

      """)

    XCTAssertEqual(
      times(ICSShiftParser.shifts(from: ics, timeZone: oslo)), ["2026-03-01 14:00 16:00"])
  }

  // MARK: - Overnight and midnight

  internal func testOvernightShiftKeepsStartDate() {
    let ics: String = calendar(
      """
      BEGIN:VEVENT\r
      DTSTART;TZID=Europe/Oslo:20260228T220000\r
      DTEND;TZID=Europe/Oslo:20260301T060000\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      DTSTART;TZID=Europe/Oslo:20260305T160000\r
      DTEND;TZID=Europe/Oslo:20260306T000000\r
      END:VEVENT\r

      """)

    XCTAssertEqual(
      times(ICSShiftParser.shifts(from: ics, timeZone: oslo)),
      ["2026-02-28 22:00 06:00", "2026-03-05 16:00 24:00"])
  }

  // MARK: - Skipped events

  internal func testSkipsAllDayCancelledZeroAndDayLongEvents() {
    let ics: String = calendar(
      """
      BEGIN:VEVENT\r
      DTSTART;VALUE=DATE:20260301\r
      DTEND;VALUE=DATE:20260302\r
      SUMMARY:Ferie\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      DTSTART:20260303\r
      DTEND:20260304\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      STATUS:CANCELLED\r
      DTSTART:20260305T080000\r
      DTEND:20260305T160000\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      DTSTART:20260306T080000\r
      DTEND:20260306T080000\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      DTSTART:20260307T080000\r
      DTEND:20260308T080000\r
      END:VEVENT\r
      BEGIN:VEVENT\r
      DTSTART:20260309T080000\r
      END:VEVENT\r

      """)

    XCTAssertTrue(ICSShiftParser.shifts(from: ics, timeZone: oslo).isEmpty)
  }

  internal func testDropsRepeatsOfTheSameShift() {
    let event: String =
      "BEGIN:VEVENT\r\nDTSTART:20260301T080000\r\nDTEND:20260301T160000\r\nEND:VEVENT\r\n"

    XCTAssertEqual(
      ICSShiftParser.shifts(from: calendar(event + event), timeZone: oslo).count, 1)
  }

  // MARK: - Line handling

  internal func testUnfoldsLinesAndIgnoresAlarmProperties() {
    let ics: String = calendar(
      """
      BEGIN:VEVENT\r
      DTSTART;TZID=Europe/Oslo:2026030\r
       1T080000\r
      DTEND;TZID=Europe/Oslo:20260301T160000\r
      SUMMARY:Lager\\, kveld\r
      \tskift\r
      BEGIN:VALARM\r
      SUMMARY:Alarm\r
      TRIGGER:-PT15M\r
      END:VALARM\r
      END:VEVENT\r

      """)

    let shifts: [CalendarImportShift] = ICSShiftParser.shifts(from: ics, timeZone: oslo)

    XCTAssertEqual(times(shifts), ["2026-03-01 08:00 16:00"])
    XCTAssertEqual(shifts.first?.title, "Lager, kveldskift")
  }

  internal func testAcceptsBareLineFeeds() {
    let ics: String =
      "BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART:20260301T080000\nDTEND:20260301T160000\nEND:VEVENT\nEND:VCALENDAR\n"

    XCTAssertEqual(
      times(ICSShiftParser.shifts(from: ics, timeZone: oslo)), ["2026-03-01 08:00 16:00"])
  }

  // MARK: - Links

  internal func testFeedURLNormalizesSchemes() {
    XCTAssertEqual(
      ICSShiftParser.feedURL(from: " webcal://services.tamigo.com/Calendar/abc/Calendar.ics \n")?
        .absoluteString,
      "https://services.tamigo.com/Calendar/abc/Calendar.ics")
    XCTAssertEqual(
      ICSShiftParser.feedURL(from: "WEBCAL://example.com/feed.ics")?.absoluteString,
      "https://example.com/feed.ics")
    XCTAssertEqual(
      ICSShiftParser.feedURL(from: "https://example.com/feed.ics")?.absoluteString,
      "https://example.com/feed.ics")
    XCTAssertEqual(
      ICSShiftParser.feedURL(from: "example.com/feed.ics")?.absoluteString,
      "https://example.com/feed.ics")
    XCTAssertNil(ICSShiftParser.feedURL(from: "ftp://example.com/feed.ics"))
    XCTAssertNil(ICSShiftParser.feedURL(from: "not a link"))
  }
}
