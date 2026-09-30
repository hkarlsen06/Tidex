import XCTest

@testable import Tidex

@MainActor
final class OnboardingFunnelRecorderTests: XCTestCase {
  private let suiteName = "OnboardingFunnelRecorderTests"
  private let userId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3"
  private var defaults: UserDefaults!
  private var signedInUserId: String?
  private var sentBatches: [[OnboardingFunnelStepRow]] = []
  private var preAuthSends: [(installId: String, step: String)] = []
  private var shouldFailSend = false
  private var shouldFailPreAuthSend = false

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
    signedInUserId = nil
    sentBatches = []
    preAuthSends = []
    shouldFailSend = false
    shouldFailPreAuthSend = false
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  func testPreAuthStepsWaitForFirstPostAuthStep() async {
    let recorder = makeRecorder()
    recorder.recordPreAuth("welcome")
    recorder.recordPreAuth("add_shift_simulator")
    await drainTasks()
    XCTAssertTrue(sentBatches.isEmpty)

    signedInUserId = userId
    recorder.record("postauth_purpose")
    await drainTasks()

    XCTAssertEqual(sentBatches.count, 1)
    XCTAssertEqual(
      sentSteps(inBatch: 0),
      ["preauth_welcome", "preauth_add_shift_simulator", "postauth_purpose"]
    )
    XCTAssertTrue(sentBatches[0].allSatisfy { $0.user_id == userId })
    XCTAssertTrue(pendingSteps.isEmpty)
  }

  func testPreAuthStepsAreSentAnonymouslyOnceWithOneInstallId() async {
    let recorder = makeRecorder()
    recorder.recordPreAuth("welcome")
    await drainTasks()
    recorder.recordPreAuth("welcome")
    await drainTasks()
    recorder.recordPreAuth("signup_screen")
    await drainTasks()

    XCTAssertEqual(preAuthSends.map(\.step).sorted(), ["signup_screen", "welcome"])
    XCTAssertEqual(Set(preAuthSends.map(\.installId)).count, 1)
    XCTAssertNotNil(UUID(uuidString: preAuthSends[0].installId))
  }

  func testFailedAnonymousSendIsRetriedWithNextPreAuthStep() async {
    shouldFailPreAuthSend = true
    let recorder = makeRecorder()
    recorder.recordPreAuth("welcome")
    await drainTasks()
    XCTAssertTrue(preAuthSends.isEmpty)

    shouldFailPreAuthSend = false
    recorder.recordPreAuth("add_shift_simulator")
    await drainTasks()

    XCTAssertEqual(preAuthSends.map(\.step).sorted(), ["add_shift_simulator", "welcome"])
  }

  func testSameStepIsSentOnlyOnce() async {
    signedInUserId = userId
    let recorder = makeRecorder()
    recorder.record("postauth_purpose")
    await drainTasks()
    recorder.record("postauth_purpose")
    await drainTasks()

    XCTAssertEqual(sentBatches.count, 1)
    XCTAssertTrue(pendingSteps.isEmpty)
  }

  func testFailedSendStaysPendingAndRetriesWithNextStep() async {
    signedInUserId = userId
    shouldFailSend = true
    let recorder = makeRecorder()
    recorder.record("postauth_purpose")
    await drainTasks()
    XCTAssertEqual(Set(pendingSteps.keys), ["postauth_purpose"])

    shouldFailSend = false
    recorder.record("postauth_wage")
    await drainTasks()

    XCTAssertEqual(sentSteps(inBatch: 0), ["postauth_purpose", "postauth_wage"])
    XCTAssertTrue(pendingSteps.isEmpty)
  }

  func testFirstShiftIsIgnoredForUsersWithoutTrackedOnboarding() async {
    let recorder = makeRecorder()
    recorder.recordPreAuth("welcome")
    signedInUserId = userId
    recorder.recordShiftCreated(method: "manual")
    await drainTasks()

    XCTAssertTrue(sentBatches.isEmpty)
    XCTAssertNil(pendingSteps[OnboardingFunnelRecorder.firstShiftStep])
  }

  func testFirstShiftIsRecordedOnceWithItsMethod() async {
    signedInUserId = userId
    let recorder = makeRecorder()
    recorder.record(OnboardingFunnelRecorder.onboardingCompletedStep)
    await drainTasks()

    recorder.recordShiftCreated(method: "recurring")
    await drainTasks()
    recorder.recordShiftCreated(method: "manual")
    await drainTasks()

    XCTAssertEqual(sentBatches.count, 2)
    XCTAssertEqual(sentSteps(inBatch: 1), ["first_shift_added", "first_shift_via_recurring"])
  }

  // MARK: - Helpers

  private var pendingSteps: [String: String] {
    defaults.dictionary(forKey: OnboardingFunnelRecorder.pendingDefaultsKey) as? [String: String]
      ?? [:]
  }

  private func makeRecorder() -> OnboardingFunnelRecorder {
    OnboardingFunnelRecorder(
      defaults: defaults,
      currentUserId: { [unowned self] in signedInUserId },
      send: { [unowned self] rows in
        if shouldFailSend { throw URLError(.notConnectedToInternet) }
        sentBatches.append(rows)
      },
      sendPreAuth: { [unowned self] installId, step, _ in
        if shouldFailPreAuthSend { throw URLError(.notConnectedToInternet) }
        preAuthSends.append((installId, step))
      }
    )
  }

  private func sentSteps(inBatch index: Int) -> Set<String> {
    guard sentBatches.indices.contains(index) else { return [] }
    return Set(sentBatches[index].map(\.step))
  }

  private func drainTasks() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }
}
