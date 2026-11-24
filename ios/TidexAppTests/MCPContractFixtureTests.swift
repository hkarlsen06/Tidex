import XCTest

@testable import Tidex

/// Rows the MCP server writes must sync into the app and price the same there. The fixture
/// comes from the server's own builders (backend/scripts/mcp-contract-fixture.ts) with the
/// gross pay its get_earnings tool computes, and a backend test keeps it current.
final class MCPContractFixtureTests: XCTestCase {
  private struct Fixture: Decodable {
    struct Total: Decodable {
      let currency: String
      let gross_pay: Double  // swiftlint:disable:this identifier_name
      let net_pay: Double  // swiftlint:disable:this identifier_name
      let tax_deducted: Double  // swiftlint:disable:this identifier_name
      let paid_hours: Double  // swiftlint:disable:this identifier_name
      let shifts: Int
    }
    struct Earnings: Decodable {
      let from: String
      let to: String
      let totals: [Total]
    }

    let user_id: String  // swiftlint:disable:this identifier_name
    let jobs: [SyncJobRow]
    let wage_snapshots: [SyncWageSnapshotRow]  // swiftlint:disable:this identifier_name
    let shifts: [SyncShiftRow]
    let earnings: Earnings
  }

  private func fixtureData() throws -> Data {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "MCPContractFixture", withExtension: "json"),
      "MCPContractFixture.json is missing from the test bundle")
    return try Data(contentsOf: url)
  }

  func testServerRowsDecodeWithTheSyncTypesTheAppPulls() throws {
    let data = try fixtureData()
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let rawJobs = try XCTUnwrap(raw["jobs"] as? [[String: Any]])

    // SyncJobRow reads a pay period it can't decode as a calendar month instead of failing.
    for (row, json) in zip(fixture.jobs, rawJobs) where json["pay_period"] != nil {
      XCTAssertNotNil(row.pay_period, "pay period of \(row.name) didn't decode")
    }
    // The payroll code ignores overtime rules it considers invalid instead of failing.
    for snapshot in fixture.wage_snapshots.map({ $0.toWageSnapshot() })
    where snapshot.overtime.enabled {
      XCTAssertNotNil(
        snapshot.overtime.runtimeEnabledConfig, "overtime of snapshot \(snapshot.id) is ignored")
    }
  }

  func testAppPricesServerRowsAsTheServerDoes() throws {
    let fixture = try JSONDecoder().decode(Fixture.self, from: fixtureData())
    let jobs = try fixture.jobs.map { row in
      let updatedAt = try XCTUnwrap(parseJobISO8601(row.updated_at))
      return LocalJob.from(serverRow: row, serverUpdatedAt: updatedAt).toJob()
    }
    let settings = try JSONDecoder().decode(
      UserSettings.self,
      from: JSONSerialization.data(withJSONObject: [
        "user_id": fixture.user_id, "theme": "system",
      ]))
    let range = fixture.earnings
    let visibleRange = (
      start: try XCTUnwrap(Date.fromISODateString(range.from)),
      end: try XCTUnwrap(Date.fromISODateString(range.to))
    )
    let computed = PayrollEngine.computeShiftsForMonth(
      .init(
        year: 2_026, month: 12, shifts: fixture.shifts.map { $0.toShiftRow() }, recurring: [],
        snapshots: fixture.wage_snapshots.map { $0.toWageSnapshot() }, settings: settings,
        visibleRange: visibleRange, jobs: jobs)
    ).filter { $0.shiftDate >= range.from && $0.shiftDate <= range.to }

    let currencyByJob = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.currency) })
    for total in range.totals {
      let shifts = computed.filter { currencyByJob[$0.shift.job_id ?? ""] == total.currency }
      let detail = shifts.map {
        "\($0.shiftDate) \($0.startTime)-\($0.endTime): \($0.computed.gross)"
      }
      XCTAssertEqual(shifts.count, total.shifts, total.currency)
      XCTAssertEqual(
        shifts.reduce(0) { $0 + $1.computed.gross }, total.gross_pay, accuracy: 0.01,
        "\(total.currency) gross: \(detail)")
      XCTAssertEqual(
        shifts.reduce(0) { $0 + $1.netPay }, total.net_pay, accuracy: 0.01,
        "\(total.currency) net: \(detail)")
      XCTAssertEqual(
        shifts.reduce(0) { $0 + $1.taxAmount }, total.tax_deducted, accuracy: 0.01,
        "\(total.currency) tax: \(detail)")
      XCTAssertEqual(
        shifts.reduce(0) { $0 + $1.computed.paidHours }, total.paid_hours, accuracy: 0.01,
        total.currency)
    }
  }
}
