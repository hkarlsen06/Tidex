import XCTest

@testable import Tidex

final class StatsServiceCachingFingerprintTests: XCTestCase {
  func testShiftFingerprintIsOrderInvariant() {
    let first = TestFixtures.shift(
      id: "a-shift",
      shiftDate: "2026-01-10",
      startTime: "08:00",
      endTime: "16:00"
    )
    let second = TestFixtures.shift(
      id: "b-shift",
      shiftDate: "2026-01-12",
      startTime: "09:00",
      endTime: "17:00"
    )

    let forward = StatsService.fingerprintShiftsForCaching([first, second])
    let reversed = StatsService.fingerprintShiftsForCaching([second, first])

    XCTAssertEqual(forward, reversed)
  }

  func testShiftFingerprintChangesWhenShiftDataChanges() {
    let original = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "08:00",
      endTime: "16:00"
    )
    let updated = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "10:00",
      endTime: "18:00"
    )

    let originalFingerprint = StatsService.fingerprintShiftsForCaching([original])
    let updatedFingerprint = StatsService.fingerprintShiftsForCaching([updated])

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }

  func testShiftFingerprintChangesWhenCustomPauseWindowsChange() {
    let original = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "08:00",
      endTime: "16:00"
    )
    let updated = TestFixtures.shift(
      id: "same-id",
      shiftDate: "2026-02-05",
      startTime: "08:00",
      endTime: "16:00",
      customPauseWindows: CustomPauseWindows(windows: [
        PauseWindow(start: "12:00", end: "12:30")
      ])
    )

    let originalFingerprint = StatsService.fingerprintShiftsForCaching([original])
    let updatedFingerprint = StatsService.fingerprintShiftsForCaching([updated])

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }

  func testRecurringShiftFingerprintChangesWhenDateSpecificPauseWindowsChange() {
    let original = RecurringShiftRow(
      id: "recurring-1",
      user_id: "user-1",
      job_id: "job-1",
      start_time: "08:00",
      end_time: "16:00",
      repeat_interval_weeks: 0,
      selected_days: ["1": "2026-02-02"],
      end_condition: nil,
      exclusions: nil,
      date_specific_pause_windows: nil,
      date_specific_supplements: nil
    )
    let updated = RecurringShiftRow(
      id: "recurring-1",
      user_id: "user-1",
      job_id: "job-1",
      start_time: "08:00",
      end_time: "16:00",
      repeat_interval_weeks: 0,
      selected_days: ["1": "2026-02-02"],
      end_condition: nil,
      exclusions: nil,
      date_specific_pause_windows: [
        "2026-02-09": CustomPauseWindows(windows: [PauseWindow(start: "12:00", end: "12:30")])
      ],
      date_specific_supplements: nil
    )

    let originalFingerprint = StatsService.fingerprintRecurringShiftsForCaching([original])
    let updatedFingerprint = StatsService.fingerprintRecurringShiftsForCaching([updated])

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }

  func testSettingsFingerprintChangesWhenMonthlyGoalOverridesChange() {
    let original = UserSettings(
      user_id: "user-1",
      created_at: nil,
      updated_at: "2026-03-01T10:00:00Z",
      last_active: nil,
      monthly_goal: 30000,
      monthly_goals_by_month: ["2026-03": 35000],
      default_shifts_view: "calendar",
      profile_picture_url: nil,
      payroll_day: 25,
      theme: "system",
      calendar_animation_style: "horizontal",
      show_dashboard_clock_buttons: true,
      half_tax_month: 12,
      currency: "kr",
      default_startup_tab: "stats"
    )
    let updated = UserSettings(
      user_id: "user-1",
      created_at: nil,
      updated_at: "2026-03-01T10:00:00Z",
      last_active: nil,
      monthly_goal: 30000,
      monthly_goals_by_month: ["2026-03": 36000],
      default_shifts_view: "calendar",
      profile_picture_url: nil,
      payroll_day: 25,
      theme: "system",
      calendar_animation_style: "horizontal",
      show_dashboard_clock_buttons: true,
      half_tax_month: 12,
      currency: "kr",
      default_startup_tab: "stats"
    )

    let originalFingerprint = StatsService.fingerprintSettingsForCaching(original)
    let updatedFingerprint = StatsService.fingerprintSettingsForCaching(updated)

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }

  func testJobsFingerprintChangesWhenCurrencyChanges() {
    let original = [
      TestFixtures.job(id: "job-1", isDefault: true, currency: "kr")
    ]
    let updated = [
      TestFixtures.job(id: "job-1", isDefault: true, currency: "$")
    ]

    let originalFingerprint = StatsService.fingerprintJobsForCaching(original)
    let updatedFingerprint = StatsService.fingerprintJobsForCaching(updated)

    XCTAssertNotEqual(originalFingerprint, updatedFingerprint)
  }
}
