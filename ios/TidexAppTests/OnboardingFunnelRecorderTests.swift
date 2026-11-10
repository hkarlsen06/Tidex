import XCTest

@testable import Tidex

@MainActor
final class OnboardingFunnelRecorderTests: XCTestCase {
  @MainActor private final class UserBox {
    var id: String?
  }

  func testDebugRecorderHasNoBackendAndKeepsNothingToSendLater() async throws {
    XCTAssertNil(OnboardingFunnelRecorder.Transport.live)

    let (defaults, suiteName) = makeDefaults()
    let recorder = OnboardingFunnelRecorder(defaults: defaults, currentUserId: { "user-1" })
    recorder.recordPreAuth("welcome")
    recorder.record("postauth_purpose")
    recorder.recordShiftCreated(method: "manual")
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertTrue(defaults.persistentDomain(forName: suiteName)?.isEmpty ?? true)
  }

  func testPreAuthStepIsSentAnonymouslyThenCarriedToTheAccount() async {
    let anonymousSent = expectation(description: "anonymous send")
    let accountSent = expectation(description: "account send")
    nonisolated(unsafe) var anonymousSteps: [String] = []
    nonisolated(unsafe) var accountRows: [OnboardingFunnelStepRow] = []
    let user = UserBox()
    let recorder = OnboardingFunnelRecorder(
      defaults: makeDefaults().defaults,
      currentUserId: { user.id },
      transport: .init(
        send: { rows in
          accountRows = rows
          accountSent.fulfill()
        },
        sendPreAuth: { _, step, _ in
          anonymousSteps.append(step)
          anonymousSent.fulfill()
        }))

    recorder.recordPreAuth("demo_skipped")
    await fulfillment(of: [anonymousSent], timeout: 2)
    user.id = "user-1"
    recorder.record("postauth_purpose")
    await fulfillment(of: [accountSent], timeout: 2)

    XCTAssertEqual(anonymousSteps, ["demo_skipped"])
    XCTAssertEqual(
      Set(accountRows.map(\.step)), ["preauth_demo_skipped", "postauth_purpose"])
    XCTAssertEqual(Set(accountRows.map(\.user_id)), ["user-1"])
  }

  private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "OnboardingFunnelRecorderTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
    return (defaults, suiteName)
  }
}
