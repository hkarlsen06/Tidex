import XCTest

@testable import Tidex

@MainActor
final class AddShiftSubmissionTests: XCTestCase {
  private enum SaveFailure: Error {
    case unavailable
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

  private func makeModel() throws -> (AddShiftViewModel, UserDefaults) {
    let defaults = try XCTUnwrap(
      UserDefaults(suiteName: "AddShiftSubmissionTests.\(UUID().uuidString)"))
    return (AddShiftViewModel(draftDefaults: defaults), defaults)
  }
}
