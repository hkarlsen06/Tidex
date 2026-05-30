import XCTest

@testable import Tidex

final class ShiftSnapshotBuilderTests: XCTestCase {
  private let ownerUserId = "032d8c2a-9af6-4777-99f0-24e2c4058bf3"
  private let recipientUserId = "11111111-2222-4333-8444-555555555555"
  private let shiftId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
  private let recurringId = "12345678-1234-4234-8234-1234567890ab"

  func testOwnShiftSnapshotBuilderHidesEarningsWhenRecipientCannotSeeThem() {
    let builder = OwnShiftSnapshotBuilder(
      shift: makeShift(),
      jobName: "Cafe",
      jobColorHex: "#FFAA00",
      currency: "kr",
      ownerUserId: ownerUserId,
      ownerDisplayName: "Hjalmar",
      ownerAvatarUrl: "https://example.com/avatar.png"
    )

    let draft = builder.build(
      for: ShareRecipient(
        id: recipientUserId,
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
    XCTAssertEqual(draft.snapshot.ownerUserId, ownerUserId)
    XCTAssertEqual(draft.snapshot.shiftId, shiftId)
  }

  func testOwnShiftSnapshotBuilderIncludesEarningsWhenRecipientCanSeeThem() {
    let builder = OwnShiftSnapshotBuilder(
      shift: makeShift(),
      jobName: "Cafe",
      jobColorHex: "#FFAA00",
      currency: "kr",
      ownerUserId: ownerUserId,
      ownerDisplayName: "Hjalmar",
      ownerAvatarUrl: nil
    )

    let draft = builder.build(
      for: ShareRecipient(
        id: recipientUserId,
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

  func testOwnShiftSnapshotBuilderUsesRecurringIdForVirtualShiftSnapshots() {
    let builder = OwnShiftSnapshotBuilder(
      shift: makeVirtualShift(),
      jobName: "Cafe",
      jobColorHex: "#FFAA00",
      currency: "kr",
      ownerUserId: ownerUserId,
      ownerDisplayName: "Hjalmar",
      ownerAvatarUrl: nil
    )

    let draft = builder.build(
      for: ShareRecipient(
        id: recipientUserId,
        displayName: "Friend",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: true
      )
    )

    XCTAssertEqual(draft.snapshot.shiftId, recurringId)
    XCTAssertEqual(draft.snapshot.ownerUserId, ownerUserId)
  }

  func testSharedShiftSnapshotBuilderFreezesHiddenSharedShiftWithoutEarnings() {
    let builder = SharedShiftSnapshotBuilder(
      shift: makeShift(),
      jobName: "Cafe",
      jobColorHex: "#FFAA00",
      currency: "kr",
      owner: SharedUser(
        id: ownerUserId,
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

    XCTAssertEqual(draft.snapshot.ownerUserId, ownerUserId)
    XCTAssertEqual(draft.snapshot.ownerDisplayName, "Mina")
    XCTAssertFalse(draft.snapshot.includesEarnings)
    XCTAssertNil(draft.snapshot.grossPay)
    XCTAssertNil(draft.snapshot.netPay)
  }
}

private func makeShift() -> ShiftWithComputations {
  ShiftWithComputations(
    shift: ShiftRow(
      id: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
      user_id: "032d8c2a-9af6-4777-99f0-24e2c4058bf3",
      job_id: "99999999-8888-4777-8666-555555555555",
      shift_date: "2026-03-11",
      start_time: "09:00",
      end_time: "17:00",
      custom_pause_windows: nil,
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

private func makeVirtualShift() -> ShiftWithComputations {
  ShiftWithComputations(
    shift: ShiftRow(
      id: "virtual-2026-03-11",
      user_id: "032d8c2a-9af6-4777-99f0-24e2c4058bf3",
      job_id: "99999999-8888-4777-8666-555555555555",
      shift_date: "2026-03-11",
      start_time: "16:00",
      end_time: "23:15",
      custom_pause_windows: nil,
      custom_supplements: nil,
      recurring_id: "12345678-1234-4234-8234-1234567890ab",
      recurring_anchor_weekday: 3
    ),
    computed: ShiftComputed(
      id: "virtual-2026-03-11",
      durationHours: 7.25,
      paidHours: 6.75,
      basePay: 1100,
      supplementPay: 210,
      gross: 1310,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    ),
    taxEnabled: true,
    taxPercentage: 10
  )
}
