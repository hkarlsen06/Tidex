import XCTest

@testable import Tidex

internal final class ISO8601TimestampTests: XCTestCase {
  private let expected = Date(timeIntervalSince1970: 1_790_590_530)  // 2026-09-28T10:15:30Z

  internal func testParsesSupabaseForms() throws {
    let inputs = [
      "2026-09-28T10:15:30Z",
      "2026-09-28T10:15:30+00:00",
      "2026-09-28T10:15:30.123Z",
      "2026-09-28T10:15:30.123456+00:00",
      "2026-09-28T12:15:30.5+02:00",
    ]
    for input in inputs {
      let date = try XCTUnwrap(ISO8601Timestamp.date(from: input), input)
      XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1, input)
    }
  }

  internal func testKeepsFractionalSeconds() throws {
    let date = try XCTUnwrap(ISO8601Timestamp.date(from: "2026-09-28T10:15:30.250Z"))
    XCTAssertEqual(date.timeIntervalSince1970, 1_790_590_530.25, accuracy: 0.0001)
  }

  internal func testRejectsInvalidInput() {
    for input in ["", "2026-09-28", "not a date", "2026-09-28 10:15:30"] {
      XCTAssertNil(ISO8601Timestamp.date(from: input), input)
    }
  }

  internal func testRoundTrips() throws {
    let date = Date(timeIntervalSince1970: 1_790_590_530.123)
    let parsed = try XCTUnwrap(ISO8601Timestamp.date(from: ISO8601Timestamp.string(from: date)))
    XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
  }

  // MARK: - LocalJob's Postgres-form normalization (normalizeJobTimestamp + parseJobISO8601)

  internal func testParsesPostgresSpaceSeparatorWithTwoDigitOffset() throws {
    let date = try XCTUnwrap(parseJobISO8601("2026-09-28 10:15:30+00"))
    XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
  }

  internal func testParsesPostgresFourDigitOffset() throws {
    let date = try XCTUnwrap(parseJobISO8601("2026-09-28T10:15:30+0000"))
    XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
  }

  internal func testParsesPostgresSpaceSeparatorWithFourDigitOffset() throws {
    // 12:15:30+02:00 == 10:15:30Z
    let date = try XCTUnwrap(parseJobISO8601("2026-09-28 12:15:30+0200"))
    XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
  }

  internal func testParsesPostgresFractionalSecondsWithTwoDigitOffset() throws {
    let date = try XCTUnwrap(parseJobISO8601("2026-09-28 10:15:30.250+00"))
    XCTAssertEqual(date.timeIntervalSince1970, 1_790_590_530.25, accuracy: 0.0001)
  }

  internal func testParseJobISO8601RejectsBlankInput() {
    XCTAssertNil(parseJobISO8601(""))
    XCTAssertNil(parseJobISO8601("   "))
  }
}
