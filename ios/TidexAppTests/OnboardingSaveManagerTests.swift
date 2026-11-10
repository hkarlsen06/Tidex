import XCTest

@testable import Tidex

final class OnboardingFirstShiftCarryoverStoreTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: "OnboardingFirstShiftCarryoverStoreTests")
    defaults.removePersistentDomain(forName: "OnboardingFirstShiftCarryoverStoreTests")
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: "OnboardingFirstShiftCarryoverStoreTests")
    defaults = nil
    super.tearDown()
  }

  private func date(_ iso: String, _ time: String) -> Date {
    let day = iso.split(separator: "-").compactMap { Int($0) }
    let clock = time.split(separator: ":").compactMap { Int($0) }
    let components = DateComponents(
      year: day[0], month: day[1], day: day[2], hour: clock[0], minute: clock[1])
    return Calendar.current.date(from: components) ?? .distantPast
  }

  private func storedAddShiftDraft() -> ShiftDraft? {
    defaults.data(forKey: ShiftDraft.userDefaultsKey)
      .flatMap { try? JSONDecoder().decode(ShiftDraft.self, from: $0) }
  }

  func testMoveCopiesSimulatorShiftIntoAddShiftDraft() {
    let now = date("2026-09-20", "12:00")
    OnboardingFirstShiftCarryoverStore.write(
      dates: ["2026-09-14", "2026-09-15"],
      startTime: date("2026-09-20", "08:00"),
      endTime: date("2026-09-20", "16:00"),
      defaults: defaults
    )

    XCTAssertTrue(
      OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(now: now, defaults: defaults))

    let draft = storedAddShiftDraft()
    XCTAssertEqual(draft?.mode, .single)
    XCTAssertEqual(draft?.selectedDates, ["2026-09-14", "2026-09-15"])
    XCTAssertEqual(draft?.startTime, "08:00")
    XCTAssertEqual(draft?.endTime, "16:00")
    XCTAssertNil(draft?.jobId)
    XCTAssertEqual(draft?.lastModified, now)
  }

  func testMoveKeepsDatesFromEveryMonthAndConsumesCarryover() {
    OnboardingFirstShiftCarryoverStore.write(
      dates: ["2026-08-31", "2026-09-01"],
      startTime: date("2026-09-01", "22:00"),
      endTime: date("2026-09-01", "06:00"),
      defaults: defaults
    )

    OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(
      now: date("2026-09-02", "09:00"), defaults: defaults)

    XCTAssertEqual(storedAddShiftDraft()?.selectedDates, ["2026-08-31", "2026-09-01"])
    XCTAssertFalse(
      OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(defaults: defaults),
      "The carry-over is used once"
    )
  }
}

@MainActor
final class CarriedDemoShiftSaveTests: XCTestCase {
  private struct SavedShift: Equatable {
    let userId: String
    let jobId: String
    let date: String
    let startTime: String
    let endTime: String
  }

  private struct Offline: Error {}

  private var defaults: UserDefaults!

  override func setUp() async throws {
    try await super.setUp()
    defaults = UserDefaults(suiteName: "CarriedDemoShiftSaveTests")
    defaults.removePersistentDomain(forName: "CarriedDemoShiftSaveTests")
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: "CarriedDemoShiftSaveTests")
    defaults = nil
    try await super.tearDown()
  }

  private func carryOverOvernightShift(dates: Set<String>) throws -> CarriedDemoShift {
    let calendar = Calendar.current
    let start = try XCTUnwrap(calendar.date(bySettingHour: 22, minute: 0, second: 0, of: .now))
    let end = try XCTUnwrap(calendar.date(bySettingHour: 6, minute: 0, second: 0, of: .now))
    OnboardingFirstShiftCarryoverStore.write(
      dates: dates, startTime: start, endTime: end, defaults: defaults)
    return try XCTUnwrap(OnboardingFirstShiftCarryoverStore.read(defaults: defaults))
  }

  func testKeptShiftBecomesOneShiftPerDateOnTheSetupJobAcrossMonths() async throws {
    let carried = try carryOverOvernightShift(dates: ["2026-11-01", "2026-10-31"])
    var saved: [SavedShift] = []
    let manager = OnboardingSaveManager(defaults: defaults) { userId, jobId, date, start, end in
      saved.append(
        SavedShift(
          userId: userId, jobId: jobId, date: date.toISODateString(), startTime: start,
          endTime: end))
    }

    let didSave = await manager.keepCarriedShift(carried, userId: "user-1", jobId: "job-1")

    XCTAssertTrue(didSave)
    XCTAssertEqual(
      saved,
      ["2026-10-31", "2026-11-01"].map {
        SavedShift(userId: "user-1", jobId: "job-1", date: $0, startTime: "22:00", endTime: "06:00")
      })
    XCTAssertNil(
      OnboardingFirstShiftCarryoverStore.read(defaults: defaults),
      "A saved shift must not be offered again on Home")
  }

  func testRetryAfterAFailedDateSavesEveryDateExactlyOnce() async throws {
    let carried = try carryOverOvernightShift(dates: ["2026-10-31", "2026-11-01"])
    var saved: [String] = []
    var failNovember = true
    let manager = OnboardingSaveManager(defaults: defaults) { _, _, date, _, _ in
      let iso = date.toISODateString()
      if iso == "2026-11-01", failNovember {
        throw Offline()
      }
      saved.append(iso)
    }

    let firstAttempt = await manager.keepCarriedShift(carried, userId: "user-1", jobId: "job-1")
    XCTAssertFalse(firstAttempt)
    guard case .error = manager.carriedShiftStatus else {
      return XCTFail("A failed save must end in the error state, got \(manager.carriedShiftStatus)")
    }
    XCTAssertNotNil(
      OnboardingFirstShiftCarryoverStore.read(defaults: defaults),
      "An unsaved shift stays carried so it can still be saved")

    failNovember = false
    let retry = await manager.keepCarriedShift(carried, userId: "user-1", jobId: "job-1")

    XCTAssertTrue(retry)
    XCTAssertEqual(saved, ["2026-10-31", "2026-11-01"], "October must not be saved twice")
    XCTAssertEqual(manager.carriedShiftStatus, .success)
  }

  /// Declining runs no save and clears the carry-over, the same call sign-out makes.
  func testDeclinedShiftIsNotOfferedOnHomeOrInTheAddScreen() throws {
    _ = try carryOverOvernightShift(dates: ["2026-10-31"])

    OnboardingFirstShiftCarryoverStore.clear(defaults: defaults)

    XCTAssertNil(OnboardingFirstShiftCarryoverStore.read(defaults: defaults))
    XCTAssertFalse(
      OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(defaults: defaults),
      "Home must not pre-fill the Add screen with a declined shift")
  }
}

@MainActor
final class OnboardingCompletionStoreTests: XCTestCase {
  private struct OfflineError: Error {}

  private var defaults: UserDefaults!

  override func setUp() async throws {
    try await super.setUp()
    defaults = UserDefaults(suiteName: "OnboardingCompletionStoreTests")
    defaults.removePersistentDomain(forName: "OnboardingCompletionStoreTests")
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: "OnboardingCompletionStoreTests")
    defaults = nil
    try await super.tearDown()
  }

  func testFailedMetadataUpdateKeepsCompletionAndStaysQueued() async {
    OnboardingCompletionStore.markCompleted(userId: "user-1", defaults: defaults)

    await OnboardingCompletionStore.retryPendingMetadataIfNeeded(
      userId: "user-1", defaults: defaults, updateMetadata: { throw OfflineError() })

    XCTAssertTrue(OnboardingCompletionStore.isCompletedLocally(userId: "user-1", defaults: defaults))
    XCTAssertTrue(
      OnboardingCompletionStore.hasPendingMetadataUpdate(userId: "user-1", defaults: defaults))
  }

  func testRetrySendsQueuedUpdateOnceAndClearsIt() async {
    OnboardingCompletionStore.markCompleted(userId: "user-1", defaults: defaults)
    var calls = 0

    await OnboardingCompletionStore.retryPendingMetadataIfNeeded(
      userId: "user-1", defaults: defaults, updateMetadata: { calls += 1 })
    await OnboardingCompletionStore.retryPendingMetadataIfNeeded(
      userId: "user-1", defaults: defaults, updateMetadata: { calls += 1 })

    XCTAssertEqual(calls, 1)
    XCTAssertFalse(
      OnboardingCompletionStore.hasPendingMetadataUpdate(userId: "user-1", defaults: defaults))
    XCTAssertTrue(OnboardingCompletionStore.isCompletedLocally(userId: "user-1", defaults: defaults))
  }

  func testMarkingAgainAfterMetadataSyncedDoesNotQueueAnotherUpdate() async {
    OnboardingCompletionStore.markCompleted(userId: "user-1", defaults: defaults)
    await OnboardingCompletionStore.retryPendingMetadataIfNeeded(
      userId: "user-1", defaults: defaults, updateMetadata: {})

    OnboardingCompletionStore.markCompleted(userId: "user-1", defaults: defaults)

    XCTAssertFalse(
      OnboardingCompletionStore.hasPendingMetadataUpdate(userId: "user-1", defaults: defaults))
  }
}
