import Supabase
import XCTest

@testable import Tidex

internal final class AdminAPITests: XCTestCase {
  private func user(
    id: String = "u1", name: String? = nil, email: String? = nil, phone: String? = nil,
    language: String? = nil
  )
    -> AdminUser
  {
    AdminUser(
      id: id, email: email, phone: phone, name: name, avatarUrl: nil, lastSignInAt: nil,
      createdAt: "2026-09-28T10:00:00.123456+00:00", isBanned: false, isAdmin: false,
      isSuperAdmin: false, language: language)
  }

  private func filledDraft() -> AdminBroadcastDraft {
    AdminBroadcastDraft(title: "Hi", body: "News", titleNo: "Hei", bodyNo: "Nytt")
  }

  // MARK: Users query

  // MARK: Broadcast draft

  internal func testSpecificTargetNeedsRecipients() {
    var draft: AdminBroadcastDraft = filledDraft()
    draft.target = .specific
    XCTAssertNotNil(draft.problem)

    draft.recipients = [user()]
    XCTAssertNil(draft.problem)
  }

  internal func testRPCParamsSendRecipientIDsOnlyForSpecificTarget() {
    var draft: AdminBroadcastDraft = filledDraft()
    draft.recipients = [user(id: "a"), user(id: "b")]
    XCTAssertEqual(draft.rpcParams["p_specific_user_ids"], .null)

    draft.target = .specific
    XCTAssertEqual(draft.rpcParams["p_specific_user_ids"], .array([.string("a"), .string("b")]))
  }

  internal func testEveryoneAudienceNeedsBothLanguagesEvenWithStaleRecipients() {
    var draft: AdminBroadcastDraft = AdminBroadcastDraft(title: "Hi", body: "News")
    draft.recipients = [user(language: "en")]

    XCTAssertEqual(draft.requiredLanguages, [.english, .norwegian])
    XCTAssertNotNil(draft.problem)
  }

  internal func testUserStatsDecodeServerShape() throws {
    let json: Data = Data(
      #"""
      {"devices":[{"id":"d1","platform":"ios","timeZone":"Europe/Oslo","appVersion":"2.7.2",
        "lastSeenAt":"2026-09-28T06:24:30.077426+00:00"}],
       "jobCount":1,"eventCount":15,"shiftCount":165,"messagesSent":622,"reportsFiled":5,
       "feedbackCount":11,"firstShiftDate":"2025-04-09","seesShiftsFrom":10,"hasCalendarFeed":true,
       "latestShiftDate":null,"reportsReceived":2,"lastShiftAddedAt":"2026-07-23T11:13:59.973667+00:00",
       "shiftsLast30Days":0,"messagesLast30Days":16,"upcomingShiftCount":0,"sharesTheirShiftsWith":10,
       "calendarFeedLastUsedAt":null,"recurringScheduleCount":2}
      """#.utf8)

    let stats: AdminUserStats = try JSONDecoder().decode(AdminUserStats.self, from: json)

    XCTAssertEqual(stats.shiftCount, 165)
    XCTAssertNil(stats.latestShift)
    XCTAssertNotNil(stats.lastShiftAdded)
    XCTAssertEqual(stats.devices.first?.appVersion, "2.7.2")
    XCTAssertNil(stats.appActivity)
    let firstShift: Date = try XCTUnwrap(stats.firstShift)
    let day: Date.ISO8601FormatStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month()
      .day()
    XCTAssertEqual(day.format(firstShift), "2025-04-09")
  }

  // MARK: App activity codes

  // MARK: Errors

  // MARK: Display helpers
}

// MARK: - Wage setup

extension AdminAPITests {
  internal func testWageSetupDecodesTableRows() throws {
    let json: Data = Data(
      #"""
      {"jobs":[{"id":"j1","name":"Rema 1000","color":"#3B82F6","user_id":"u1","currency":"kr",
        "revision":1,"created_at":"2026-10-06T16:13:57.559+00:00","deleted_at":null,"is_default":true,
        "pay_period":null,"sort_order":0,"updated_at":"2026-10-06T16:13:57.559+00:00",
        "archived_at":null,"payroll_day":15,"monthly_goal":20000,"half_tax_month":null}],
       "settings":{"currency":"kr","payrollDay":20,"monthlyGoal":null,"halfTaxMonth":12},
       "snapshots":[{"id":"s1","job_id":"j1","user_id":"u1",
        "overtime":{"rules":[],"enabled":false,"weeklyThresholdHours":40},"from_date":null,
        "created_at":"2026-10-06T16:13:57.559+00:00","deleted_at":null,"wage_level":null,
        "hourly_wage":197.96,"supplements":{"rules":[
          {"to":"21:00","days":[1,2,3,4,5],"from":"18:00","rate":22},
          {"to":"23:00","days":[6],"from":"18:00","rate":110}]},
        "tax_enabled":true,"break_method":"proportional","break_enabled":true,"tariff_type_id":null,
        "tax_percentage":18,"break_threshold_hours":5.5,"break_deduction_minutes":30},
        {"id":"s2","job_id":"other","user_id":"u1","from_date":"2026-01-01","hourly_wage":205,
         "supplements":{"rules":[]},"overtime":{"rules":[],"enabled":false,"weeklyThresholdHours":40}}],
       "adjustments":[{"id":"a1","user_id":"u1","job_id":"j1","amount":1500.5,"currency":"kr",
        "category":"retro_pay","tax_treatment":"gross_taxable","description":"Back pay","note":null,
        "payout_date":"2026-09-20","revision":1,"deleted_at":null}]}
      """#.utf8)

    let setup: AdminWageSetup = try JSONDecoder().decode(AdminWageSetup.self, from: json)

    let job: Job = try XCTUnwrap(setup.jobs.first)
    XCTAssertEqual(job.name, "Rema 1000")
    let snapshots: [WageSnapshot] = setup.snapshots(for: job)
    XCTAssertEqual(snapshots.map(\.id), ["s1"])
    let snapshot: WageSnapshot = try XCTUnwrap(snapshots.first)
    XCTAssertEqual(snapshot.hourly_wage, 197.96)
    XCTAssertEqual(snapshot.effectiveTaxPercentage, 18)
    XCTAssertEqual(snapshot.breakMethod, .proportional)
    XCTAssertEqual(snapshot.effectiveSupplements.map(\.rate), [22, 110])
    XCTAssertEqual(setup.settings?.halfTaxMonth, 12)
    XCTAssertEqual(setup.adjustments.first?.description, "Back pay")
    XCTAssertEqual(setup.adjustments.first?.category, .retroPay)
  }
}
