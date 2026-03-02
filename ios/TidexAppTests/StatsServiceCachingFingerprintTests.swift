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
}
