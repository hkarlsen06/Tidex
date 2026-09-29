import XCTest

@testable import Tidex

@MainActor
final class OnboardingSaveManagerTests: XCTestCase {
  func testSaveStatusAllowsCompletionOnlyAfterSuccess() {
    XCTAssertFalse(OnboardingSaveManager.SaveStatus.idle.allowsCompletion)
    XCTAssertFalse(OnboardingSaveManager.SaveStatus.saving.allowsCompletion)
    XCTAssertFalse(OnboardingSaveManager.SaveStatus.error.allowsCompletion)
    XCTAssertTrue(OnboardingSaveManager.SaveStatus.success.allowsCompletion)
  }

  func testPrepareForSaveBlocksCompletionUntilSaveSucceeds() {
    let manager = OnboardingSaveManager()

    manager.prepareForSave(completionMode: .friendOnlySkip)

    XCTAssertEqual(manager.status, .saving)
    XCTAssertNil(manager.errorMessage)
    XCTAssertFalse(manager.status.allowsCompletion)
  }

  func testDefaultJobNameUsesEnglishLocale() {
    let name = OnboardingSaveManager.defaultJobName(locale: Locale(identifier: "en"))

    XCTAssertEqual(name, "Job")
  }

  func testDefaultJobNameUsesNorwegianLocale() {
    let name = OnboardingSaveManager.defaultJobName(locale: Locale(identifier: "nb"))

    XCTAssertEqual(name, "Jobb")
  }
}

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
    XCTAssertEqual(draft?.isExpired, false)
  }

  func testMoveDropsDatesOutsideCurrentMonthAndConsumesCarryover() {
    OnboardingFirstShiftCarryoverStore.write(
      dates: ["2026-08-31", "2026-09-01"],
      startTime: date("2026-09-01", "22:00"),
      endTime: date("2026-09-01", "06:00"),
      defaults: defaults
    )

    OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(
      now: date("2026-09-02", "09:00"), defaults: defaults)

    XCTAssertEqual(storedAddShiftDraft()?.selectedDates, ["2026-09-01"])
    XCTAssertFalse(
      OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(defaults: defaults),
      "The carry-over is used once"
    )
  }

  func testMoveWithoutSimulatorShiftLeavesAddShiftDraftUntouched() {
    XCTAssertFalse(OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(defaults: defaults))
    XCTAssertNil(defaults.data(forKey: ShiftDraft.userDefaultsKey))
  }

  func testClearDropsSimulatorShift() {
    OnboardingFirstShiftCarryoverStore.write(
      dates: ["2026-09-14"], startTime: nil, endTime: nil, defaults: defaults)

    OnboardingFirstShiftCarryoverStore.clear(defaults: defaults)

    XCTAssertFalse(OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft(defaults: defaults))
  }
}

@MainActor
final class OnboardingCompletionStoreTests: XCTestCase {
  private struct OfflineError: Error {}

  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: "OnboardingCompletionStoreTests")
    defaults.removePersistentDomain(forName: "OnboardingCompletionStoreTests")
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: "OnboardingCompletionStoreTests")
    defaults = nil
    super.tearDown()
  }

  func testCompletionIsLocalAndQueuedBeforeAnyNetworkCall() {
    OnboardingCompletionStore.markCompleted(userId: "user-1", defaults: defaults)

    XCTAssertTrue(OnboardingCompletionStore.isCompletedLocally(userId: "user-1", defaults: defaults))
    XCTAssertTrue(
      OnboardingCompletionStore.hasPendingMetadataUpdate(userId: "user-1", defaults: defaults))
    XCTAssertFalse(OnboardingCompletionStore.isCompletedLocally(userId: "user-2", defaults: defaults))
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
