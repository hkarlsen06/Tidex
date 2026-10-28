import UserNotifications
import XCTest

@testable import Tidex

@MainActor
final class NotificationPermissionTests: XCTestCase {
  func testOtherAccountAndSignedOutPushesContainNoPrivateContent() throws {
    let payload: [AnyHashable: Any] = [
      "recipient_user_id": "account-a", "thread_id": "private-thread", "sender_name": "Private sender",
    ]
    for signedIn in ["account-b", nil] {
      let content = try XCTUnwrap(
        NotificationRecipientPrivacy.redactedContent(userInfo: payload, signedInUserId: signedIn))
      XCTAssertTrue(content.body.isEmpty)
      XCTAssertTrue(content.subtitle.isEmpty)
      XCTAssertTrue(content.userInfo.isEmpty)
      XCTAssertTrue(content.attachments.isEmpty)
      XCTAssertTrue(content.categoryIdentifier.isEmpty)
      XCTAssertNil(content.sound)
      XCTAssertNil(content.badge)
    }
    XCTAssertNil(
      NotificationRecipientPrivacy.redactedContent(userInfo: payload, signedInUserId: "ACCOUNT-A"))
  }

  func testContextualRequestPromptsOnceAndRegistersAfterGrant() async {
    var status = UNAuthorizationStatus.notDetermined
    var requests = 0
    var registrations = 0
    let service = NotificationService(
      authorizationStatus: { status },
      requestAuthorization: {
        requests += 1
        status = .authorized
        return true
      },
      registerForPush: { registrations += 1 },
      isAppActive: { true }
    )

    await service.requestPermissionAndRegister()
    await service.requestPermissionAndRegister()

    XCTAssertEqual(requests, 1)
    XCTAssertEqual(registrations, 2)
  }

  func testStartupDoesNotRequestUndeterminedPermission() async {
    let service = NotificationService(
      authorizationStatus: { .notDetermined },
      requestAuthorization: {
        XCTFail("Startup must not prompt")
        return true
      },
      registerForPush: { XCTFail("Permission has not been granted") },
      isAppActive: { true }
    )

    await service.registerIfPermissionAlreadyGranted()
  }

  func testEnteringBackgroundWhileCheckingPermissionDoesNotPrompt() async {
    var appIsActive = true
    let service = NotificationService(
      authorizationStatus: {
        appIsActive = false
        return .notDetermined
      },
      requestAuthorization: {
        XCTFail("The app must still be active after checking permission")
        return true
      },
      registerForPush: {},
      isAppActive: { appIsActive }
    )

    await service.requestPermissionAndRegister()
  }

  func testRequestErrorAllowsRetryOnNextContextualAction() async {
    var requests = 0
    let service = NotificationService(
      authorizationStatus: { .notDetermined },
      requestAuthorization: {
        requests += 1
        throw URLError(.timedOut)
      },
      registerForPush: { XCTFail("Failed permission requests must not register") },
      isAppActive: { true }
    )

    await service.requestPermissionAndRegister()
    await service.requestPermissionAndRegister()

    XCTAssertEqual(requests, 2)
  }

  func testConcurrentActionsShareOnePermissionRequest() async {
    var requestCount = 0
    var continuation: CheckedContinuation<Bool, Never>?
    let service = NotificationService(
      authorizationStatus: { .notDetermined },
      requestAuthorization: {
        requestCount += 1
        return await withCheckedContinuation { continuation = $0 }
      },
      registerForPush: {},
      isAppActive: { true }
    )

    let firstRequest = Task { await service.requestPermissionAndRegister() }
    while continuation == nil { await Task.yield() }
    await service.requestPermissionAndRegister()
    continuation?.resume(returning: false)
    await firstRequest.value

    XCTAssertEqual(requestCount, 1)
  }
}
