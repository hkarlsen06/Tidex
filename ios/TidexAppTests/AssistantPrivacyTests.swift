import AppIntents
import XCTest

@testable import Tidex

/// Spotlight and Siri keep what the app gives them across sign-outs and account switches, so
/// they may only ever get the signed-in user's own data.
@MainActor
final class AssistantPrivacyTests: XCTestCase {
  private let userId = "user-1"
  private let now = Calendar.gregorianCurrent.date(
    from: DateComponents(year: 2_026, month: 11, day: 4, hour: 12)) ?? .distantPast
  private let jobs = [TestFixtures.job(id: "cafe", isDefault: true)]
  private var shifts: [ShiftWithComputations] {
    [
      TestFixtures.computedShift(
        id: "tomorrow", shiftDate: "2026-11-05", startTime: "22:00", endTime: "06:00",
        jobId: "cafe", gross: 1_600),
      TestFixtures.computedShift(
        id: "next-year", shiftDate: "2027-03-01", startTime: "09:00", endTime: "17:00",
        jobId: "cafe", gross: 1_600),
    ]
  }

  func testSpotlightGetsTheSignedInUsersShiftsInTheWindowAndActiveJobs() async {
    let index = RecordingIndex()

    await AssistantSpotlight.reindex(
      userId: userId, shifts: shifts, jobs: jobs, now: now, access: .user(id: userId),
      index: index)

    XCTAssertEqual(index.deletedTypes, ["ShiftEntity", "JobEntity"])
    XCTAssertEqual(index.indexed, ["ShiftEntity:tomorrow", "JobEntity:cafe"])
  }

  func testImpersonationEmptiesSpotlightAndIndexesNothing() async {
    let index = RecordingIndex()

    await AssistantSpotlight.reindex(
      userId: userId, shifts: shifts, jobs: jobs, now: now, access: .impersonating, index: index)

    XCTAssertEqual(index.deletedTypes, ["ShiftEntity", "JobEntity"])
    XCTAssertEqual(index.indexed, [])
  }

  func testARefreshForAnotherAccountIndexesNothing() async {
    for access: AssistantAccess in [.user(id: "user-2"), .signedOut] {
      let index = RecordingIndex()

      await AssistantSpotlight.reindex(
        userId: userId, shifts: shifts, jobs: jobs, now: now, access: access, index: index)

      XCTAssertEqual(index.indexed, [], "\(access)")
    }
  }

  func testSignOutRemovesEverythingTheAppIndexed() async {
    let index = RecordingIndex()

    await AssistantSpotlight.removeAll(index: index)

    XCTAssertTrue(index.deletedAll)
  }

  func testImpersonatingAdminsAndSignedOutDevicesGetNoShifts() async {
    let access = [
      AssistantAccess(session: session(isImpersonating: true)),
      AssistantAccess(session: nil),
    ]
    XCTAssertEqual(access, [.impersonating, .signedOut])

    for access in access {
      do {
        _ = try await AssistantShifts.entities(access: access, now: now)
        XCTFail("\(access) must not read shifts")
      } catch let error as AssistantError {
        XCTAssertEqual(error, access == .impersonating ? .impersonating : .signedOut)
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
    XCTAssertEqual(AssistantAccess(session: session(isImpersonating: false)), .user(id: userId))
  }

  private func session(isImpersonating: Bool) -> AuthSession {
    AuthSession(
      user: AuthUser(
        id: userId.uppercased(), email: nil, name: nil, avatarUrl: nil, role: "admin",
        termsAcceptedAt: nil, finishedOnboarding: true, isImpersonating: isImpersonating,
        actorId: "admin-1"),
      accessToken: "",
      expiresAt: 0,
      clerkSessionId: "session-1"
    )
  }
}

@MainActor
private final class RecordingIndex: AssistantSearchIndex {
  var indexed: [String] = []
  var deletedTypes: [String] = []
  var deletedAll = false

  func indexAppEntities(_ appEntities: [some IndexedEntity], priority: Int) {
    indexed += appEntities.map { "\(type(of: $0)):\($0.id)" }
  }

  func deleteAppEntities<Entity: IndexedEntity>(ofType entityType: Entity.Type) {
    deletedTypes.append("\(entityType)")
  }

  func deleteAllSearchableItems() {
    deletedAll = true
  }
}
