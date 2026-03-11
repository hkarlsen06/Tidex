import XCTest

@testable import Tidex

final class ShiftSnapshotBuilderTests: XCTestCase {
  func testOwnShiftSnapshotBuilderHidesEarningsWhenRecipientCannotSeeThem() {
    let builder = OwnShiftSnapshotBuilder(
      shift: makeShift(),
      jobName: "Cafe",
      jobColorHex: "#FFAA00",
      currency: "kr",
      ownerUserId: "viewer-1",
      ownerDisplayName: "Hjalmar",
      ownerAvatarUrl: "https://example.com/avatar.png"
    )

    let draft = builder.build(
      for: ShareRecipient(
        id: "friend-1",
        displayName: "Friend",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      )
    )

    XCTAssertFalse(draft.snapshot.includesEarnings)
    XCTAssertNil(draft.snapshot.grossPay)
    XCTAssertNil(draft.snapshot.netPay)
    XCTAssertEqual(draft.snapshot.ownerDisplayName, "Hjalmar")
  }

  func testOwnShiftSnapshotBuilderIncludesEarningsWhenRecipientCanSeeThem() {
    let builder = OwnShiftSnapshotBuilder(
      shift: makeShift(),
      jobName: "Cafe",
      jobColorHex: "#FFAA00",
      currency: "kr",
      ownerUserId: "viewer-1",
      ownerDisplayName: "Hjalmar",
      ownerAvatarUrl: nil
    )

    let draft = builder.build(
      for: ShareRecipient(
        id: "friend-1",
        displayName: "Friend",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: true
      )
    )

    XCTAssertTrue(draft.snapshot.includesEarnings)
    XCTAssertEqual(draft.snapshot.grossPay, 1200)
    XCTAssertEqual(draft.snapshot.netPay, 1050)
  }

  func testSharedShiftSnapshotBuilderFreezesHiddenSharedShiftWithoutEarnings() {
    let builder = SharedShiftSnapshotBuilder(
      shift: makeShift(),
      jobName: "Cafe",
      jobColorHex: "#FFAA00",
      currency: "kr",
      owner: SharedUser(
        id: "owner-1",
        email: "owner@example.com",
        phone: nil,
        firstName: "Mina",
        profilePictureUrl: "https://example.com/owner.png",
        oauthAvatarUrl: nil,
        sharedAt: "2026-03-11T10:00:00Z",
        showEarnings: false,
        hidden: false
      )
    )

    let draft = builder.build()

    XCTAssertEqual(draft.snapshot.ownerUserId, "owner-1")
    XCTAssertEqual(draft.snapshot.ownerDisplayName, "Mina")
    XCTAssertFalse(draft.snapshot.includesEarnings)
    XCTAssertNil(draft.snapshot.grossPay)
    XCTAssertNil(draft.snapshot.netPay)
  }
}

private func makeShift() -> ShiftWithComputations {
  ShiftWithComputations(
    shift: ShiftRow(
      id: "shift-1",
      user_id: "viewer-1",
      job_id: "job-1",
      shift_date: "2026-03-11",
      start_time: "09:00",
      end_time: "17:00",
      custom_supplements: nil
    ),
    computed: ShiftComputed(
      id: "shift-1",
      durationHours: 8,
      paidHours: 7.5,
      basePay: 1000,
      supplementPay: 200,
      gross: 1200,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    ),
    taxEnabled: true,
    taxPercentage: 12.5
  )
}
