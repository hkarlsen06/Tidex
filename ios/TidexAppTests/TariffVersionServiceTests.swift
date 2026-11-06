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
  func testExpiredCatalogueDoesNotFallBackToSupersededRatesOffline() async throws {
    var current = version("reviewed", effective: "2026-11-06", level1: 215.29)
    current.validThrough = "2028-12-31"
    let saved = [current, version("superseded", effective: "2025-04-01", level1: 204.79)]
    let online = makeService(versions: { _ in saved })
    _ = try await online.getTariffVersions(tariffType: "hk_retail")
    let offline = makeService()
    let expired = try await offline.getTariffVersionForDate(
      tariffType: "hk_retail", date: "2029-01-01")
    let valid = try await offline.getTariffVersionForDate(
      tariffType: "hk_retail", date: "2028-12-31")
    XCTAssertNil(expired)
    XCTAssertEqual(valid?.rate(forLevel: 1), 215.29)
  }

  @MainActor
  func testMissingOrMismatchedTariffCannotResolveAnUnrelatedRetailWage() {
    let data = OnboardingData()
    data.wageType = .tariff
    data.selectedTariffTypeId = "riksavtalen_hotel"
    XCTAssertFalse(data.hasValidWageSelection)
    XCTAssertEqual(data.resolvedHourlyWage, 0)
    data.currentTariffVersion = version("retail", effective: "2026-06-01", level1: 195.04)
    XCTAssertFalse(data.hasValidWageSelection)
    XCTAssertEqual(data.resolvedHourlyWage, 0)
  }

  @MainActor
  func testAdditionalCategoryCanBeSelectedAndResolvesItsOwnPay() throws {
    let payload = """
      {"id":"hotel","tariff_type_id":"riksavtalen_hotel","effective_date":"2026-11-06",
       "rates":{"1":215.29,"7":218.90},"supplements":{"rules":[]},
       "categories":[{"level":7,"label_en":"Other staff, 2 years","label_nb":"Øvrige, 2 år"},
                     {"level":1,"label_en":"Other staff, entry","label_nb":"Øvrige, begynner"}]}
      """
    let decoded = try JSONDecoder().decode(TariffVersion.self, from: Data(payload.utf8))
    let levels = TariffLevel.from(tariffVersion: decoded)
    let data = OnboardingData()
    data.wageType = .tariff
    data.selectedTariffTypeId = decoded.tariff_type_id
    data.currentTariffVersion = decoded
    data.selectedTariffLevel = try XCTUnwrap(levels.first).level
    XCTAssertEqual(levels.map(\.level), [7, 1])
    XCTAssertTrue(data.hasValidWageSelection)
    XCTAssertEqual(data.resolvedHourlyWage, 218.90)
  }

  func testEditingSupplementRetainsItsHolidayAndPayBasis() throws {
    let payload = """
      {"days":[1,2,3,4,5,6,7],"from":"00:00","to":"24:00","percent":100,
       "stackingGroup":"holiday","dates":["2026-12-25"],"excludedDates":["2026-12-26"],
       "minimumRate":70,"percentageBaseRate":246.22,
       "shiftStartDates":["2026-12-24"],"excludedShiftStartDates":["2026-12-23"]}
      """
    let decoded = try JSONDecoder().decode(SupplementRule.self, from: Data(payload.utf8))
    var draft = OnboardingSupplementRule(from: decoded)
    draft.value = 125
    let saved = draft.toSupplementRule()
    XCTAssertEqual(saved.percent, 125)
    XCTAssertEqual(saved.dates, decoded.dates)
    XCTAssertEqual(saved.excludedDates, decoded.excludedDates)
    XCTAssertEqual(saved.stackingGroup, decoded.stackingGroup)
    XCTAssertEqual(saved.minimumRate, decoded.minimumRate)
    XCTAssertEqual(saved.percentageBaseRate, decoded.percentageBaseRate)
    XCTAssertEqual(saved.shiftStartDates, decoded.shiftStartDates)
    XCTAssertEqual(saved.excludedShiftStartDates, decoded.excludedShiftStartDates)
  }

}
