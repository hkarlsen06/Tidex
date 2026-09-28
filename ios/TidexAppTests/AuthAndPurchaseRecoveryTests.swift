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

  // MARK: - MFA assurance level

  internal func testAssuranceLevelReadsAAL1AndAAL2Claims() {
    XCTAssertEqual(AppCoordinator.assuranceLevel(fromAccessToken: Self.jwt(aal: "aal1")), "aal1")
    XCTAssertEqual(AppCoordinator.assuranceLevel(fromAccessToken: Self.jwt(aal: "aal2")), "aal2")
  }

  internal func testAssuranceLevelIsNilForMalformedToken() {
    XCTAssertNil(AppCoordinator.assuranceLevel(fromAccessToken: "not-a-jwt"))
    XCTAssertNil(AppCoordinator.assuranceLevel(fromAccessToken: "a.%%%.c"))
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

  private static func jwt(aal: String) -> String {
    let payload = Data(#"{"sub":"user","aal":"\#(aal)"}"#.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "header.\(payload).signature"
  }
}
