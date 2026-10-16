import XCTest

@testable import Tidex

internal final class AppGateTests: XCTestCase {
  internal func testOlderVersionIsBlockedForUpdate() {
    let config: AppGateConfig = AppGateConfig(minimumVersion: "3.1.0", maintenance: false)

    XCTAssertEqual(AppGateConfig.block(for: config, appVersion: "3.0.9"), .updateRequired)
  }

  internal func testSameOrNewerVersionIsNotBlocked() {
    let config: AppGateConfig = AppGateConfig(minimumVersion: "3.1.0", maintenance: false)

    XCTAssertNil(AppGateConfig.block(for: config, appVersion: "3.1.0"))
    XCTAssertNil(AppGateConfig.block(for: config, appVersion: "3.10.0"))
  }

  internal func testMaintenanceBlocksCurrentVersion() {
    let config: AppGateConfig = AppGateConfig(minimumVersion: "3.0.0", maintenance: true)

    XCTAssertEqual(AppGateConfig.block(for: config, appVersion: "3.0.0"), .maintenance)
  }

  internal func testUpdateWinsOverMaintenance() {
    let config: AppGateConfig = AppGateConfig(minimumVersion: "4.0.0", maintenance: true)

    XCTAssertEqual(AppGateConfig.block(for: config, appVersion: "3.0.0"), .updateRequired)
  }

  internal func testMissingFieldsDoNotBlock() throws {
    let config: AppGateConfig = try JSONDecoder().decode(AppGateConfig.self, from: Data("{}".utf8))

    XCTAssertNil(AppGateConfig.block(for: config, appVersion: "1.0"))
  }

  internal func testVersionComparisonTreatsMissingPartsAsZero() {
    XCTAssertFalse(AppGateConfig.isVersion("3.0", olderThan: "3.0.0"))
    XCTAssertTrue(AppGateConfig.isVersion("3.0", olderThan: "3.0.1"))
    XCTAssertFalse(AppGateConfig.isVersion("3.0.1", olderThan: "3"))
    XCTAssertTrue(AppGateConfig.isVersion("2.9.9", olderThan: "3"))
  }
}
