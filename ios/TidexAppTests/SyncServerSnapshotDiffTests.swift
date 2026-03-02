import XCTest

@testable import Tidex

final class SyncServerSnapshotDiffTests: XCTestCase {
  func testUserShiftServerSnapshotChangedFields() {
    let timestamp = Date.fromDateAndTime("2026-03-02", time: "10:00") ?? Date()

    let original = UserShiftServerSnapshot.from(
      jobId: "job-1",
      shiftDate: "2026-03-02",
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil,
      updatedAt: timestamp,
      revision: 1,
      deletedAt: nil
    )

    let updated = UserShiftServerSnapshot.from(
      jobId: "job-2",
      shiftDate: "2026-03-02",
      startTime: "09:00",
      endTime: "18:00",
      customSupplements: CustomSupplementsData(rules: []),
      updatedAt: timestamp,
      revision: 2,
      deletedAt: nil
    )

    XCTAssertEqual(
      updated.changedFields(from: original),
      Set([.jobId, .endTime, .customSupplements])
    )
  }

  func testRecurringShiftServerSnapshotChangedFields() throws {
    let timestamp = Date.fromDateAndTime("2026-03-02", time: "10:00") ?? Date()
    let selectedDaysOriginal = try canonicalJSONEncoder.encode(["1": "2026-03-02"] as SelectedDays)
    let selectedDaysUpdated = try canonicalJSONEncoder.encode(
      ["1": "2026-03-02", "2": "2026-03-03"] as SelectedDays)

    let original = RecurringShiftServerSnapshot(
      jobId: "job-1",
      startTime: "09:00",
      endTime: "17:00",
      repeatIntervalWeeks: 1,
      selectedDays: selectedDaysOriginal,
      endCondition: nil,
      exclusions: nil,
      dateSpecificSupplements: nil,
      updatedAt: timestamp,
      revision: 1,
      deletedAt: nil
    )

    let updated = RecurringShiftServerSnapshot(
      jobId: "job-1",
      startTime: "10:00",
      endTime: "17:00",
      repeatIntervalWeeks: 2,
      selectedDays: selectedDaysUpdated,
      endCondition: nil,
      exclusions: nil,
      dateSpecificSupplements: nil,
      updatedAt: timestamp,
      revision: 2,
      deletedAt: nil
    )

    XCTAssertEqual(
      updated.changedFields(from: original),
      Set([.startTime, .repeatIntervalWeeks, .selectedDays])
    )
  }

  func testWageSnapshotServerSnapshotChangedFields() throws {
    let timestamp = Date.fromDateAndTime("2026-03-02", time: "10:00") ?? Date()
    let originalSupplements = try canonicalJSONEncoder.encode(SupplementRulesSnapshot(rules: []))
    let updatedSupplements = try canonicalJSONEncoder.encode(
      SupplementRulesSnapshot(
        rules: [SupplementRule(days: [1], from: "18:00", to: "24:00", rate: 22)]
      )
    )

    let original = WageSnapshotServerSnapshot(
      jobId: "job-1",
      fromDate: "2026-01-01",
      hourlyWage: 200,
      wageLevel: nil,
      tariffTypeId: nil,
      supplements: originalSupplements,
      taxEnabled: true,
      taxPercentage: 20,
      breakEnabled: true,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30,
      updatedAt: timestamp,
      revision: 1,
      deletedAt: nil
    )

    let updated = WageSnapshotServerSnapshot(
      jobId: "job-1",
      fromDate: "2026-01-01",
      hourlyWage: 220,
      wageLevel: nil,
      tariffTypeId: "hk_retail",
      supplements: updatedSupplements,
      taxEnabled: true,
      taxPercentage: 18,
      breakEnabled: true,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30,
      updatedAt: timestamp,
      revision: 2,
      deletedAt: nil
    )

    XCTAssertEqual(
      updated.changedFields(from: original),
      Set([.hourlyWage, .tariffTypeId, .supplements, .taxPercentage])
    )
  }

  func testJobServerSnapshotChangedFields() {
    let timestamp = Date.fromDateAndTime("2026-03-02", time: "10:00") ?? Date()

    let original = JobServerSnapshot(
      name: "Store",
      color: "#FF0000",
      isDefault: true,
      sortOrder: 0,
      payrollDay: 25,
      halfTaxMonth: 12,
      monthlyGoal: 30000,
      archivedAt: nil,
      deletedAt: nil,
      updatedAt: timestamp,
      revision: 1
    )

    let updated = JobServerSnapshot(
      name: "Store",
      color: "#00FF00",
      isDefault: false,
      sortOrder: 0,
      payrollDay: 20,
      halfTaxMonth: 12,
      monthlyGoal: 30000,
      archivedAt: timestamp,
      deletedAt: nil,
      updatedAt: timestamp,
      revision: 2
    )

    XCTAssertEqual(
      updated.changedFields(from: original),
      Set([.color, .isDefault, .payrollDay, .archivedAt])
    )
  }

  func testUserSettingsServerSnapshotChangedFields() {
    let timestamp = Date.fromDateAndTime("2026-03-02", time: "10:00") ?? Date()

    let original = UserSettingsServerSnapshot(
      monthlyGoal: 20000,
      monthlyGoalsByMonth: ["2026-03": 25000],
      defaultShiftsView: "calendar",
      profilePictureUrl: nil,
      payrollDay: 25,
      theme: "system",
      calendarAnimationStyle: "horizontal",
      showDashboardClockButtons: true,
      halfTaxMonth: nil,
      currency: "NOK",
      defaultStartupTab: "home",
      lastActive: nil,
      updatedAt: timestamp,
      revision: 1
    )

    let updated = UserSettingsServerSnapshot(
      monthlyGoal: 22000,
      monthlyGoalsByMonth: ["2026-03": 26000],
      defaultShiftsView: "list",
      profilePictureUrl: nil,
      payrollDay: 25,
      theme: "dark",
      calendarAnimationStyle: "horizontal",
      showDashboardClockButtons: false,
      halfTaxMonth: nil,
      currency: "NOK",
      defaultStartupTab: "home",
      lastActive: nil,
      updatedAt: timestamp,
      revision: 2
    )

    XCTAssertEqual(
      updated.changedFields(from: original),
      Set([
        .monthlyGoal, .monthlyGoalsByMonth, .defaultShiftsView, .theme, .showDashboardClockButtons,
      ])
    )
  }

  func testUserSettingsServerSnapshotDecodeBackfillsNewFields() throws {
    let json = """
      {
        "monthlyGoal": null,
        "defaultShiftsView": "calendar",
        "profilePictureUrl": null,
        "payrollDay": 15,
        "theme": "system",
        "calendarAnimationStyle": "horizontal",
        "halfTaxMonth": null,
        "currency": "NOK",
        "defaultStartupTab": "home",
        "lastActive": null,
        "updatedAt": "2026-03-02T12:00:00Z",
        "revision": 10
      }
      """
    let jsonData = Data(json.utf8)

    let decoded = try syncJSONDecoder.decode(UserSettingsServerSnapshot.self, from: jsonData)

    XCTAssertEqual(decoded.monthlyGoalsByMonth, [:])
    XCTAssertTrue(decoded.showDashboardClockButtons)
  }
}
