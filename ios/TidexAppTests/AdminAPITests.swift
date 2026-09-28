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
      id: id, email: email, phone: phone, name: name, lastSignInAt: nil,
      createdAt: "2026-09-28T10:00:00.123456+00:00", isBanned: false, isAdmin: false,
      isSuperAdmin: false, language: language)
  }

  private func filledDraft() -> AdminBroadcastDraft {
    AdminBroadcastDraft(title: "Hi", body: "News", titleNo: "Hei", bodyNo: "Nytt")
  }

  // MARK: Broadcast draft

  internal func testDraftNeedsBothLanguages() {
    var draft: AdminBroadcastDraft = filledDraft()
    XCTAssertNil(draft.problem)

    draft.bodyNo = "   "
    XCTAssertNotNil(draft.problem)
  }

  internal func testSpecificTargetNeedsRecipients() {
    var draft: AdminBroadcastDraft = filledDraft()
    draft.target = .specific
    XCTAssertNotNil(draft.problem)

    draft.recipients = [user()]
    XCTAssertNil(draft.problem)
  }

  internal func testRPCParamsTrimTextAndOmitBlankDeepLinks() {
    var draft: AdminBroadcastDraft = filledDraft()
    draft.title = "  Hi  "
    draft.deeplink = " "

    let params: [String: AnyJSON] = draft.rpcParams

    XCTAssertEqual(params["p_title"], .string("Hi"))
    XCTAssertEqual(params["p_deeplink"], .null)
    XCTAssertEqual(params["p_target"], .string("all"))
    XCTAssertEqual(params["p_specific_user_ids"], .null)
  }

  internal func testRPCParamsSendRecipientIDsOnlyForSpecificTarget() {
    var draft: AdminBroadcastDraft = filledDraft()
    draft.recipients = [user(id: "a"), user(id: "b")]
    XCTAssertEqual(draft.rpcParams["p_specific_user_ids"], .null)

    draft.target = .specific
    XCTAssertEqual(draft.rpcParams["p_specific_user_ids"], .array([.string("a"), .string("b")]))
  }

  internal func testNorwegianRecipientsOnlyNeedNorwegianText() {
    var draft: AdminBroadcastDraft = AdminBroadcastDraft(titleNo: "Hei", bodyNo: "Nytt")
    draft.target = .specific
    draft.recipients = [user(id: "a", language: "no"), user(id: "b", language: "no")]

    XCTAssertEqual(draft.requiredLanguages, [.norwegian])
    XCTAssertNil(draft.problem)
    XCTAssertEqual(draft.rpcParams["p_title"], .null)
    XCTAssertEqual(draft.rpcParams["p_title_no"], .string("Hei"))
  }

  internal func testEnglishRecipientsOnlyNeedEnglishText() {
    var draft: AdminBroadcastDraft = AdminBroadcastDraft(title: "Hi", body: "News")
    draft.target = .specific
    draft.recipients = [user(language: "en")]

    XCTAssertEqual(draft.requiredLanguages, [.english])
    XCTAssertNil(draft.problem)
  }

  internal func testMixedRecipientsNeedBothLanguages() {
    var draft: AdminBroadcastDraft = AdminBroadcastDraft(title: "Hi", body: "News")
    draft.target = .specific
    draft.recipients = [user(id: "a", language: "en"), user(id: "b", language: "no")]

    XCTAssertEqual(draft.requiredLanguages, [.english, .norwegian])
    XCTAssertEqual(draft.problem, "Fill in the Norwegian title and message.")
  }

  internal func testEveryoneAudienceNeedsBothLanguagesEvenWithStaleRecipients() {
    var draft: AdminBroadcastDraft = AdminBroadcastDraft(title: "Hi", body: "News")
    draft.recipients = [user(language: "en")]

    XCTAssertEqual(draft.requiredLanguages, [.english, .norwegian])
    XCTAssertNotNil(draft.problem)
  }

  internal func testTitleOverServerLimitIsRejected() {
    var draft: AdminBroadcastDraft = filledDraft()
    draft.titleNo = String(repeating: "a", count: AdminBroadcastDraft.titleLimit + 1)

    XCTAssertEqual(draft.problem, "Titles can be at most 100 characters.")
  }

  internal func testUserWithoutLanguageGetsEnglish() {
    XCTAssertEqual(user().broadcastLanguage, .english)
    XCTAssertEqual(user(language: "no").broadcastLanguage, .norwegian)
  }

  internal func testBroadcastDetailDecodesServerShape() throws {
    let json: Data = Data(
      #"""
      {"id":"b1","title":null,"body":null,"deeplink":null,"titleNo":"Hei","bodyNo":"Test",
       "deeplinkNo":null,"target":"specific","targetCount":1,"status":"queued",
       "createdAt":"2026-09-28T06:05:05.404665+00:00","adminEmail":"a@b.no",
       "recipients":[{"id":"o1","userId":"u1","name":"Hjalmar","email":"a@b.no","phone":null,
         "title":"Hei","status":"failed","attempts":3,"deeplink":null,
         "errorMessage":"BadDeviceToken","processedAt":null}]}
      """#.utf8)

    let detail: AdminBroadcastDetail = try JSONDecoder().decode(
      AdminBroadcastDetail.self, from: json)

    XCTAssertNil(detail.title)
    XCTAssertEqual(detail.titleNo, "Hei")
    XCTAssertEqual(detail.recipients.first?.displayName, "Hjalmar")
    XCTAssertEqual(detail.recipients.first?.errorMessage, "BadDeviceToken")
    XCTAssertNotNil(detail.created)
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
    let firstShift: Date = try XCTUnwrap(stats.firstShift)
    let day: Date.ISO8601FormatStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month()
      .day()
    XCTAssertEqual(day.format(firstShift), "2025-04-09")
  }

  // MARK: Errors

  internal func testEdgeFunctionErrorUsesServerMessage() throws {
    let data: Data = try JSONSerialization.data(withJSONObject: [
      "success": false, "error": "Cannot ban another admin",
    ])

    let error: AdminError = AdminError(FunctionsError.httpError(code: 403, data: data))

    XCTAssertEqual(error.message, "Cannot ban another admin")
  }

  internal func testEdgeFunctionErrorWithoutBodyFallsBackToStatus() {
    let error: AdminError = AdminError(FunctionsError.httpError(code: 500, data: Data()))

    XCTAssertEqual(error.message, "Request failed (500)")
  }

  // MARK: Display helpers

  internal func testDisplayNameSkipsBlankFields() {
    XCTAssertEqual(user(name: " ", email: "a@b.no").displayName, "a@b.no")
    XCTAssertEqual(user(id: "1234567890").displayName, "12345678")
  }

  internal func testContactHidesValueAlreadyShownAsName() {
    XCTAssertNil(user(email: "a@b.no").contact)
    XCTAssertEqual(user(name: "Ann", email: "a@b.no").contact, "a@b.no")
    XCTAssertEqual(user(name: "Ann", phone: "+4712345678").contact, "+4712345678")
  }

  internal func testUserParsesPostgresTimestamp() {
    XCTAssertNotNil(user().created)
  }

  internal func testHumanizedAction() {
    XCTAssertEqual("shift_share_created".adminHumanized, "Shift share created")
    XCTAssertEqual("".adminHumanized, "")
  }

  internal func testAuditMetadataRowsSortAndSkipNulls() throws {
    let json: Data = Data(
      #"""
      {"id":"1","adminEmail":null,"action":"user_ban","targetUserId":null,"targetEmail":null,
       "metadata":{"ban_duration":"876000h","reason":null,"attempts":3},"createdAt":"2026-09-28T10:00:00+00:00"}
      """#.utf8)

    let entry: AdminAuditEntry = try JSONDecoder().decode(AdminAuditEntry.self, from: json)

    XCTAssertEqual(entry.metadataRows.map(\.key), ["Attempts", "Ban duration"])
    XCTAssertEqual(entry.metadataRows.last?.value, "876000h")
  }
}
