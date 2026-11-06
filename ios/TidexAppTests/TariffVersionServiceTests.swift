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

  func testSavedNightGuardRestoresItsExactArrangement() {
    let types = hotelSelectionTypes
    let selection = TariffSelection(types: types, selectedTypeID: "saved-manual-guard")
    XCTAssertEqual(selection.selectedFamilyID, "hotel-agreement")
    XCTAssertEqual(selection.selectedValues["week"], "35.5")
    XCTAssertEqual(selection.selectedValues["night-role"], "manual")
    XCTAssertEqual(selection.resolvedTypeID, "saved-manual-guard")
  }

  func testNewAgreementRequiresWeekAndNightRoleBeforeResolvingPayRules() {
    var selection = TariffSelection(types: hotelSelectionTypes)
    selection.selectFamily("hotel-agreement")
    XCTAssertNil(selection.resolvedTypeID)
    selection.selectOption(dimensionID: "night-role", value: "ordinary")
    XCTAssertNil(selection.selectedValues["night-role"])
    selection.selectOption(dimensionID: "week", value: "37.5")
    XCTAssertNil(selection.resolvedTypeID)
    selection.selectOption(dimensionID: "night-role", value: "ordinary")
    XCTAssertEqual(selection.resolvedTypeID, "hotel-standard")
  }

  func testSwitchingToApprenticeCannotKeepAnUnsupportedReducedWeek() {
    let types = [
      selectionType("employee-normal", answers: [("employment", "employee"), ("week", "37.5")]),
      selectionType("employee-reduced", answers: [("employment", "employee"), ("week", "35.5")]),
      selectionType("apprentice", answers: [("employment", "apprentice"), ("week", "37.5")]),
    ]
    var selection = TariffSelection(types: types, selectedTypeID: "employee-reduced")
    selection.selectOption(dimensionID: "employment", value: "apprentice")
    XCTAssertEqual(selection.resolvedTypeID, "apprentice")
    XCTAssertEqual(selection.selectedValues["week"], "37.5")
    XCTAssertEqual(selection.dimensions.last?.options.map(\.value), ["37.5"])
  }

  func testChangingWeekRequiresAnotherNightRoleWhenTheOldRoleIsUnsupported() {
    var selection = TariffSelection(
      types: hotelSelectionTypes, selectedTypeID: "saved-manual-guard")
    selection.selectOption(dimensionID: "week", value: "37.5")
    XCTAssertNil(selection.resolvedTypeID)
    XCTAssertNil(selection.selectedValues["night-role"])
    selection.selectOption(dimensionID: "night-role", value: "guard")
    XCTAssertEqual(selection.resolvedTypeID, "hotel-guard")
  }

  func testChangingAgreementRequiresItsOwnAnswersInsteadOfCarryingTheOldWeek() {
    let hotel = hotelSelectionTypes
    let other = [
      selectionType("other-normal", family: "other", answers: [("week", "37.5")]),
      selectionType("other-reduced", family: "other", answers: [("week", "35.5")]),
    ]
    var selection = TariffSelection(types: hotel + other, selectedTypeID: "saved-manual-guard")
    selection.selectFamily("other")
    XCTAssertNil(selection.resolvedTypeID)
    XCTAssertTrue(selection.selectedValues.isEmpty)
    selection.selectOption(dimensionID: "week", value: "37.5")
    XCTAssertEqual(selection.resolvedTypeID, "other-normal")
  }

  func testLegacyAndUnavailableSavedAgreementsRemainSelected() {
    let legacy = TariffSelection(types: [retail], selectedTypeID: retail.id)
    XCTAssertEqual(legacy.resolvedTypeID, retail.id)
    XCTAssertTrue(legacy.dimensions.isEmpty)
    let unavailable = TariffSelection(
      types: hotelSelectionTypes, selectedTypeID: "retired-agreement")
    XCTAssertEqual(unavailable.resolvedTypeID, "retired-agreement")
    XCTAssertEqual(unavailable.selectedFamily?.displayName, "retired-agreement")
  }

  func testEmptySelectionDoesNotBecomeAnUnavailableAgreement() {
    let selection = TariffSelection(types: hotelSelectionTypes, selectedTypeID: "")
    XCTAssertNil(selection.selectedFamily)
    XCTAssertNil(selection.resolvedTypeID)
    XCTAssertEqual(selection.families.count, 1)
  }

  func testServerPresentationRestoresTheConcreteAgreementSelection() throws {
    let payload = """
      {"id":"saved-guard","display_name":"Legacy label","country":"NO","is_default":false,
       "presentation":{"family_id":"hotel","name_en":"Hotel agreement","name_nb":"Hotellavtale",
       "kind":"agreement","search_terms":["Riksavtalen"],"category_group":"hotel-staff",
       "options":[{"dimension_id":"night_role","label_en":"Night guard?","label_nb":"Nattevakt?",
       "help_en":"Check your contract","help_nb":"Se arbeidsavtalen","value":"guard",
       "value_en":"Yes","value_nb":"Ja"}]}}
      """
    let type = try JSONDecoder().decode(TariffType.self, from: Data(payload.utf8))
    let selection = TariffSelection(types: [type], selectedTypeID: "saved-guard")
    XCTAssertEqual(selection.selectedFamilyID, "hotel")
    XCTAssertEqual(selection.selectedValues["night_role"], "guard")
    XCTAssertEqual(selection.resolvedTypeID, "saved-guard")
    XCTAssertTrue(selection.selectedFamily?.searchTerms.contains("Riksavtalen") == true)
  }

  func testCategoryCanOnlyCarryAcrossDeclaredCompatibleAgreementVariants() {
    let original = selectionType("original", group: "employee", answers: [("week", "37.5")])
    let reduced = selectionType("reduced", group: "employee", answers: [("week", "35.5")])
    let apprentice = selectionType("apprentice", group: "apprentice", answers: [])
    let unrelated = selectionType("other", family: "other", group: "employee", answers: [])
    XCTAssertTrue(TariffSelection.canPreserveCategory(from: original, to: reduced))
    XCTAssertFalse(TariffSelection.canPreserveCategory(from: original, to: apprentice))
    XCTAssertFalse(TariffSelection.canPreserveCategory(from: original, to: unrelated))
    XCTAssertFalse(TariffSelection.canPreserveCategory(from: original, to: retail))
    XCTAssertTrue(TariffSelection.canPreserveCategory(from: retail, to: retail))
  }

  func testPresentationSurvivesServiceCacheAndResolvesWithoutParsingNames() async throws {
    let saved = hotelSelectionTypes
    let online = makeService(types: { saved })
    _ = try await online.getTariffTypes()
    let offline = makeService()
    let types = try await offline.getTariffTypes()
    var selection = TariffSelection(types: types)
    selection.selectFamily("hotel-agreement")
    selection.selectOption(dimensionID: "week", value: "35.5")
    selection.selectOption(dimensionID: "night-role", value: "manual")
    XCTAssertEqual(selection.resolvedTypeID, "saved-manual-guard")
  }

  func testShippedCatalogueResolvesHotelAndApprenticeArrangements() throws {
    let catalogue = try TariffCatalogueFixture.load()
    var selection = TariffSelection(types: catalogue.types)
    selection.selectFamily("riksavtalen")
    selection.selectOption(dimensionID: "week", value: "35.5")
    XCTAssertNil(selection.resolvedTypeID)
    selection.selectOption(dimensionID: "night_role", value: "manual")
    XCTAssertEqual(selection.resolvedTypeID, "riksavtalen_manual_355")
    selection.selectFamily("cleaning_nho")
    selection.selectOption(dimensionID: "employment", value: "apprentice")
    XCTAssertEqual(selection.resolvedTypeID, "cleaning_nho_apprentice")
    XCTAssertEqual(selection.dimensions.last?.options.map(\.value), ["37.5"])
  }

}

extension TariffVersionServiceTests {
  fileprivate var hotelSelectionTypes: [TariffType] {
    [
      selectionType(
        "hotel-standard", family: "hotel-agreement",
        answers: [("week", "37.5"), ("night-role", "ordinary")]),
      selectionType(
        "hotel-guard", family: "hotel-agreement",
        answers: [("week", "37.5"), ("night-role", "guard")]),
      selectionType(
        "hotel-reduced", family: "hotel-agreement",
        answers: [("week", "35.5"), ("night-role", "ordinary")]),
      selectionType(
        "saved-manual-guard", family: "hotel-agreement",
        answers: [("week", "35.5"), ("night-role", "manual")]),
    ]
  }

  fileprivate func selectionType(
    _ id: String, family: String = "cleaning", group: String = "employee",
    answers: [(String, String)]
  ) -> TariffType {
    TariffType(
      id: id, display_name: "Same display name", description: nil, country: "NO", is_default: false,
      presentation: TariffPresentation(
        familyID: family, nameEnglish: "Agreement", nameNorwegian: "Avtale", kind: .agreement,
        searchTerms: [], categoryGroup: group,
        options: answers.map { dimension, value in
          TariffPresentationOption(
            dimensionID: dimension, labelEnglish: dimension, labelNorwegian: dimension,
            value: value, valueEnglish: value, valueNorwegian: value)
        }))
  }
}
