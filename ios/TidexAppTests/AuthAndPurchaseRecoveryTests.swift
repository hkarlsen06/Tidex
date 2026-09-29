import Supabase
import XCTest

@testable import Tidex

internal final class AuthAndPurchaseRecoveryTests: XCTestCase {
  // MARK: - Password recovery callback

  internal func testPKCERecoveryCallbackWithoutTypeIsRecovery() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://login-callback/recovery?code=abc123"))

    XCTAssertTrue(AppLifecycleHandler.isPasswordRecoveryCallback(url))
  }

  internal func testImplicitRecoveryCallbackWithTypeFragmentIsRecovery() throws {
    let url: URL = try XCTUnwrap(
      URL(string: "tidex://login-callback#access_token=a&refresh_token=b&type=recovery")
    )

    XCTAssertTrue(AppLifecycleHandler.isPasswordRecoveryCallback(url))
  }

  internal func testLoginCallbackIsNotRecovery() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://login-callback?code=abc123"))

    XCTAssertFalse(AppLifecycleHandler.isPasswordRecoveryCallback(url))
  }

  internal func testPercentEncodedTypeInQueryIsRecovery() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://login-callback?type=recover%79"))

    XCTAssertTrue(AppLifecycleHandler.isPasswordRecoveryCallback(url))
  }

  internal func testPercentEncodedTypeInFragmentIsRecovery() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://login-callback#type=recover%79"))

    XCTAssertTrue(AppLifecycleHandler.isPasswordRecoveryCallback(url))
  }

  internal func testQueryTypeOverridesFragmentType() throws {
    // The query is merged after the fragment, so it wins when both carry `type`.
    let url: URL = try XCTUnwrap(
      URL(string: "tidex://login-callback?type=recovery#type=signup")
    )

    XCTAssertTrue(AppLifecycleHandler.isPasswordRecoveryCallback(url))
  }

  // MARK: - MFA assurance level

  internal func testAssuranceLevelReadsAAL1AndAAL2Claims() {
    XCTAssertEqual(AppCoordinator.assuranceLevel(fromAccessToken: Self.jwt(aal: "aal1")), "aal1")
    XCTAssertEqual(AppCoordinator.assuranceLevel(fromAccessToken: Self.jwt(aal: "aal2")), "aal2")
  }

  internal func testAssuranceLevelIsNilForMalformedToken() {
    XCTAssertNil(AppCoordinator.assuranceLevel(fromAccessToken: "not-a-jwt"))
    XCTAssertNil(AppCoordinator.assuranceLevel(fromAccessToken: "a.%%%.c"))
  }

  @MainActor
  internal func testVerifiedImpersonationResumesWithoutTargetMFA() async throws {
    let target = try Self.session(aal: "aal1")
    let route = await AppCoordinator.resolveMFARoute(
      session: target, isImpersonating: { true },
      validateImpersonation: { target }, currentSession: { nil })

    guard case .resume(let session) = route else {
      return XCTFail("A server-verified impersonation must not ask for the target's TOTP")
    }
    XCTAssertEqual(session.accessToken, target.accessToken)
  }

  @MainActor
  internal func testExpiredImpersonationRoutesTheRestoredAdminSession() async throws {
    let target = try Self.session(aal: "aal1")
    let admin = try Self.session(aal: "aal2")
    var isImpersonating = true
    let route = await AppCoordinator.resolveMFARoute(
      session: target, isImpersonating: { isImpersonating },
      validateImpersonation: {
        isImpersonating = false
        return nil
      },
      currentSession: { admin })

    guard case .resume(let session) = route else {
      return XCTFail("An expired impersonation must route using the restored admin session")
    }
    XCTAssertEqual(session.accessToken, admin.accessToken)
  }

  @MainActor
  internal func testUnverifiedImpersonationWaitsAndOrdinaryAAL1StillRequiresMFA() async throws {
    let session = try Self.session(aal: "aal1")
    let unverified = await AppCoordinator.resolveMFARoute(
      session: session, isImpersonating: { true },
      validateImpersonation: { nil }, currentSession: { session })
    guard case .retry = unverified else {
      return XCTFail("Stored impersonation metadata alone must not bypass MFA")
    }

    let ordinary = await AppCoordinator.resolveMFARoute(
      session: session, isImpersonating: { false },
      validateImpersonation: { nil }, currentSession: { session })
    guard case .verification(let factor) = ordinary else {
      return XCTFail("An ordinary AAL1 session must still verify its TOTP factor")
    }
    XCTAssertEqual(factor.id, "factor-1")
  }

  // MARK: - Attachment upload errors

  internal func testDuplicateAttachmentUploadIsTreatedAsUploaded() {
    let duplicate = StorageError(
      statusCode: "409",
      message: "The resource already exists",
      error: "Duplicate"
    )

    XCTAssertNil(FriendsMessagingService.attachmentUploadFailure(duplicate))
  }

  internal func testRejectedAttachmentUploadIsNotANetworkError() {
    let rejected = StorageError(statusCode: "403", message: "new row violates row-level security")

    let failure = FriendsMessagingService.attachmentUploadFailure(rejected)

    guard case .httpError(let statusCode, _) = failure as? FriendsMessagingServiceError else {
      return XCTFail("Expected httpError, got \(String(describing: failure))")
    }
    XCTAssertEqual(statusCode, 403)
  }

  internal func testTransportFailureIsANetworkError() {
    let failure = FriendsMessagingService.attachmentUploadFailure(URLError(.notConnectedToInternet))

    guard case .networkError = failure as? FriendsMessagingServiceError else {
      return XCTFail("Expected networkError, got \(String(describing: failure))")
    }
  }

  // MARK: - Helpers

  private static func session(aal: String) throws -> Session {
    let json = #"""
      {"id":"032d8c2a-9af6-4777-99f0-24e2c4058bf3","aud":"authenticated",
       "app_metadata":{},"user_metadata":{},
       "created_at":"2026-09-01T00:00:00Z","updated_at":"2026-09-01T00:00:00Z",
       "factors":[{"id":"factor-1","factor_type":"totp","status":"verified",
         "created_at":"2026-09-01T00:00:00Z","updated_at":"2026-09-01T00:00:00Z"}]}
      """#
    return Session(
      accessToken: jwt(aal: aal), tokenType: "bearer", expiresIn: 3_600,
      expiresAt: Date().timeIntervalSince1970 + 3_600, refreshToken: "refresh-token",
      user: try AuthClient.Configuration.jsonDecoder.decode(User.self, from: Data(json.utf8)))
  }

  private static func jwt(aal: String) -> String {
    let payload = Data(#"{"sub":"user","aal":"\#(aal)"}"#.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "header.\(payload).signature"
  }
}
