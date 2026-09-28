import Supabase
import XCTest

@testable import Tidex

internal final class AdminAPITests: XCTestCase {
  private func user(
    id: String = "u1", name: String? = nil, email: String? = nil, phone: String? = nil
  )
    -> AdminUser
  {
    AdminUser(
      id: id, email: email, phone: phone, name: name, lastSignInAt: nil,
      createdAt: "2026-09-28T10:00:00.123456+00:00", isBanned: false, isAdmin: false,
      isSuperAdmin: false)
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
