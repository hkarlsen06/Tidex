import XCTest

@testable import Tidex

final class TariffVersionServiceTests: XCTestCase {
  private struct OfflineError: Error {}

  private var cacheURL: URL!

  override func setUp() {
    super.setUp()
    cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("TariffVersionServiceTests-\(UUID().uuidString).json")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: cacheURL)
    super.tearDown()
  }

  private let retail = TariffType(
    id: "hk_retail", display_name: "HK Detaljhandel", description: nil, country: "NO",
    is_default: true)

  private func version(_ id: String, effective: String, level1: Double) -> TariffVersion {
    TariffVersion(
      id: id, tariff_type_id: "hk_retail", effective_date: effective, name: nil,
      rates: ["1": level1], supplements: SupplementRulesSnapshot(rules: []), overtime: nil)
  }

  private func makeService(
    types: @escaping TariffVersionService.FetchTypes = { throw OfflineError() },
    versions: @escaping TariffVersionService.FetchVersions = { _ in throw OfflineError() },
    versionForDate: @escaping TariffVersionService.FetchVersionForDate = { _, _ in
      throw OfflineError()
    }
  ) -> TariffVersionService {
    TariffVersionService(
      cacheURL: cacheURL, fetchTypes: types, fetchVersions: versions,
      fetchVersionForDate: versionForDate)
  }

  func testTypesSurviveRelaunchWhenNetworkFails() async throws {
    let saved = retail
    let online = makeService(types: { [saved] })
    _ = try await online.getTariffTypes()

    // A new instance stands in for a relaunch, with the network down.
    let offline = makeService()
    let types = try await offline.getTariffTypes()

    XCTAssertEqual(types, [retail])
  }

  func testVersionsSurviveRelaunchWhenNetworkFails() async throws {
    let saved = [version("v2", effective: "2026-04-01", level1: 200)]
    let online = makeService(versions: { _ in saved })
    _ = try await online.getTariffVersions(tariffType: "hk_retail")

    let offline = makeService()
    let versions = try await offline.getTariffVersions(tariffType: "hk_retail")

    XCTAssertEqual(versions, saved)
  }

  func testThrowsWhenNetworkFailsAndNothingIsSaved() async {
    let service = makeService()

    do {
      _ = try await service.getTariffTypes()
      XCTFail("Expected an error with no network and no saved data")
    } catch {
      XCTAssertTrue(error is OfflineError)
    }
  }

  func testDateLookupUsesSavedVersionsWhenNetworkFails() async throws {
    let saved = [
      version("v2", effective: "2026-04-01", level1: 200),
      version("v1", effective: "2025-04-01", level1: 190),
    ]
    let online = makeService(versions: { _ in saved })
    _ = try await online.getTariffVersions(tariffType: "hk_retail")

    let offline = makeService()
    let inV2 = try await offline.getTariffVersionForDate(
      tariffType: "hk_retail", date: "2026-09-29")
    let inV1 = try await offline.getTariffVersionForDate(
      tariffType: "hk_retail", date: "2025-12-01")
    let beforeAll = try await offline.getTariffVersionForDate(
      tariffType: "hk_retail", date: "2024-01-01")

    XCTAssertEqual(inV2?.id, "v2")
    XCTAssertEqual(inV1?.id, "v1")
    XCTAssertNil(beforeAll)
  }

  func testDateLookupThrowsWhenNetworkFailsAndVersionsAreNotSaved() async {
    let service = makeService()

    do {
      _ = try await service.getTariffVersionForDate(tariffType: "hk_retail", date: "2026-09-29")
      XCTFail("Expected an error with no network and no saved versions")
    } catch {
      XCTAssertTrue(error is OfflineError)
    }
  }
}
