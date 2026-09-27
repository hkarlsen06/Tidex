import XCTest

@testable import Tidex

@MainActor
final class AddShiftSubmissionTests: XCTestCase {
  private enum SaveFailure: Error {
    case unavailable
  }

  func testEarningsPreviewUsesTheWorkplacesPayoutTaxSettings() throws {
    let settings = try JSONDecoder().decode(
      UserSettings.self,
      from: Data(#"{"user_id":"user-1","theme":"system","half_tax_month":11}"#.utf8))
    for halfTaxMonth: Int? in [11, nil] {
      let job = TestFixtures.job(id: "job", isDefault: true, halfTaxMonth: halfTaxMonth)
      let snapshots = [
        TestFixtures.wageSnapshot(
          taxEnabled: true, taxPercentage: 20, breakEnabled: false, jobId: job.id),
        TestFixtures.wageSnapshot(
          fromDate: "2026-11-01", taxEnabled: true, taxPercentage: 30,
          breakEnabled: false, jobId: job.id),
      ]
      let preview = try XCTUnwrap(
        AddShiftViewModel.computeEarningsForDate(
          "2026-10-31", startTime: "22:00", endTime: "02:00",
          context: .init(
            requiresExplicitJobSelection: false, selectedJobId: job.id, effectiveJobId: job.id,
            snapshots: snapshots, jobs: [job], configuredJobIds: [job.id], settings: settings)))
      XCTAssertEqual(preview.gross, 800, accuracy: 0.001)
      XCTAssertEqual(preview.net, halfTaxMonth == 11 ? 680 : 560, accuracy: 0.001)
    }
  }

  func testPartialSaveRetainsOnlyUnsavedDatesAndRetryDoesNotDuplicateShifts() async throws {
    let (model, defaults) = try makeModel()
    defer { model.clearDraft() }
    let dates = ["2026-09-30", "2026-10-01", "2026-10-02"]
    model.selectedDates = Set(dates)
    var saved: [String] = []

    do {
      try await model.saveSelectedSingleShifts { date in
        let iso = date.toISODateString()
        if iso == dates[1] {
          throw ShiftCreationError.monthLimitReached(
            existingMonths: [DateComponents(year: 2_026, month: 9)])
        }
        saved.append(iso)
      }
      XCTFail("Expected the October shift to be blocked")
    } catch ShiftCreationError.monthLimitReached {
      // This is the same failure used by the upgrade/delete-and-retry flow.
    }

    XCTAssertEqual(saved, [dates[0]])
    XCTAssertEqual(model.selectedDates, Set(dates.suffix(2)))
    let data = try XCTUnwrap(defaults.data(forKey: ShiftDraft.userDefaultsKey))
    let draft = try JSONDecoder().decode(ShiftDraft.self, from: data)
    XCTAssertEqual(Set(draft.selectedDates), Set(dates.suffix(2)))

    try await model.saveSelectedSingleShifts { date in
      saved.append(date.toISODateString())
    }

    XCTAssertEqual(saved, dates, "Retry must never save September a second time")
    XCTAssertTrue(model.selectedDates.isEmpty)
    XCTAssertNil(defaults.data(forKey: ShiftDraft.userDefaultsKey))
  }

  func testFirstSaveFailurePreservesEverySelectedDate() async throws {
    let (model, _) = try makeModel()
    defer { model.clearDraft() }
    model.selectedDates = ["2026-09-10", "2026-09-11"]
    let originalDates = model.selectedDates

    do {
      try await model.saveSelectedSingleShifts { _ in throw SaveFailure.unavailable }
      XCTFail("Expected save failure")
    } catch SaveFailure.unavailable {
      XCTAssertEqual(model.selectedDates, originalDates)
    }
  }

  func testInvalidSelectionIsRejectedBeforeAnyShiftIsSaved() async throws {
    let (model, _) = try makeModel()
    defer { model.clearDraft() }
    model.selectedDates = ["2026-09-10", "invalid"]
    var saveCount = 0

    do {
      try await model.saveSelectedSingleShifts { _ in saveCount += 1 }
      XCTFail("Expected invalid date failure")
    } catch ShiftSaveError.invalidDate {
      XCTAssertEqual(saveCount, 0)
      XCTAssertEqual(model.selectedDates.count, 2)
    }
  }

  func testSuccessfulBatchSavesEachDateOnceInOrder() async throws {
    let (model, _) = try makeModel()
    defer { model.clearDraft() }
    model.selectedDates = ["2026-09-12", "2026-09-10"]
    var saved: [String] = []

    try await model.saveSelectedSingleShifts { date in
      saved.append(date.toISODateString())
    }

    XCTAssertEqual(saved, ["2026-09-10", "2026-09-12"])
    XCTAssertTrue(model.selectedDates.isEmpty)
  }

  func testStartFreshCannotDiscardDatesDuringSave() throws {
    let (model, _) = try makeModel()
    defer {
      model.isLoading = false
      model.clearDraft()
    }
    model.selectedDates = ["2026-09-10"]
    model.isLoading = true

    model.startFresh()

    XCTAssertEqual(model.selectedDates, ["2026-09-10"])
  }

  func testOvernightEventExplainsWhyItCannotBeSaved() throws {
    let (model, _) = try makeModel()
    defer { model.clearDraft() }
    model.mode = .events
    model.eventNote = "Dentist"
    model.startTime = try time(hour: 22)
    model.endTime = try time(hour: 2)

    XCTAssertTrue(model.eventTimesCrossMidnight)
    XCTAssertFalse(model.canSubmitEvent)
    XCTAssertEqual(model.submitBlockers, [.eventCrossesMidnight])

    model.endTime = try time(hour: 23)
    XCTAssertFalse(model.eventTimesCrossMidnight)
    XCTAssertTrue(model.submitBlockers.isEmpty)

    // Ending at midnight is the end of the same day, not an overnight event.
    model.endTime = try time(hour: 0)
    XCTAssertFalse(model.eventTimesCrossMidnight)

    model.endTime = nil
    XCTAssertFalse(model.eventTimesCrossMidnight)
    XCTAssertEqual(model.submitBlockers, [.missingTimes])
  }

  private func time(hour: Int) throws -> Date {
    try XCTUnwrap(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now))
  }

  private func makeModel() throws -> (AddShiftViewModel, UserDefaults) {
    let defaults = try XCTUnwrap(
      UserDefaults(suiteName: "AddShiftSubmissionTests.\(UUID().uuidString)"))
    return (AddShiftViewModel(draftDefaults: defaults), defaults)
  }
}
