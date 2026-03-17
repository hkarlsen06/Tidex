import XCTest

@testable import Tidex

final class FriendsListOrderingTests: XCTestCase {
  func testMessagingActivitySortsByLatestMessageBeforeShiftFallback() {
    let users = [
      makeUser(id: "active-shift", firstName: "Active"),
      makeUser(id: "older-message", firstName: "Older"),
      makeUser(id: "newer-message", firstName: "Newer"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: ["older-message"],
      chatPreviewsByUserId: [
        "older-message": FriendCardMessagePreview(
          text: "Unread",
          timestamp: Date(timeIntervalSince1970: 1_700_000_100),
          state: .incomingUnread
        ),
        "newer-message": FriendCardMessagePreview(
          text: "Seen",
          timestamp: Date(timeIntervalSince1970: 1_700_000_200),
          state: .incomingOpened
        ),
      ],
      shiftPreviews: [
        "active-shift": makeShiftPreview(
          sharerId: "active-shift",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        )
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(
      ordering.sortedSharers(users).map(\.id),
      ["newer-message", "older-message", "active-shift"]
    )
  }

  func testFallsBackToLegacyShiftOrderingWhenNoMessageStatusExists() {
    let users = [
      makeUser(id: "no-shift", firstName: "No Shift"),
      makeUser(id: "upcoming", firstName: "Upcoming"),
      makeUser(id: "active", firstName: "Active"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: [],
      chatPreviewsByUserId: [:],
      shiftPreviews: [
        "upcoming": makeShiftPreview(
          sharerId: "upcoming",
          shiftDate: "2026-03-19",
          startTime: "09:00",
          endTime: "17:00",
          status: .upcoming
        ),
        "active": makeShiftPreview(
          sharerId: "active",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        ),
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(ordering.sortedSharers(users).map(\.id), ["active", "upcoming", "no-shift"])
  }

  func testHiddenUsersWithMessageActivityArePromotedOutOfHiddenDisclosure() {
    let visible = [
      makeUser(id: "visible", firstName: "Visible", hidden: false)
    ]
    let hidden = [
      makeUser(id: "hidden-chat", firstName: "Hidden Chat", hidden: true),
      makeUser(id: "hidden-shift", firstName: "Hidden Shift", hidden: true),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: [],
      chatPreviewsByUserId: [
        "hidden-chat": FriendCardMessagePreview(
          text: "Hey",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingOpened
        )
      ],
      shiftPreviews: [
        "hidden-chat": makeShiftPreview(
          sharerId: "hidden-chat",
          shiftDate: "2026-03-20",
          startTime: "10:00",
          endTime: "18:00",
          status: .upcoming
        ),
        "hidden-shift": makeShiftPreview(
          sharerId: "hidden-shift",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        ),
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(
      ordering.visibleSharers(visible: visible, hidden: hidden).map(\.id),
      ["hidden-chat", "visible"]
    )
    XCTAssertEqual(ordering.hiddenDisclosureSharers(hidden).map(\.id), ["hidden-shift"])
    XCTAssertTrue(ordering.shouldSuppressShiftPreview(for: hidden[0]))
    XCTAssertFalse(ordering.shouldSuppressShiftPreview(for: hidden[1]))
  }

  private func makeUser(id: String, firstName: String, hidden: Bool = false) -> SharedUser {
    SharedUser(
      id: id,
      email: nil,
      phone: nil,
      firstName: firstName,
      profilePictureUrl: nil,
      oauthAvatarUrl: nil,
      sharedAt: "2026-03-01",
      showEarnings: false,
      hidden: hidden
    )
  }

  private func makeShiftPreview(
    sharerId: String,
    shiftDate: String,
    startTime: String,
    endTime: String,
    status: ShiftPreviewStatus
  ) -> SharerShiftPreview {
    SharerShiftPreview(
      sharerId: sharerId,
      shift: SharedShiftData(
        id: "\(sharerId)-shift",
        user_id: sharerId,
        job_id: nil,
        job_name: nil,
        job_color: nil,
        shift_date: shiftDate,
        start_time: startTime,
        end_time: endTime,
        computed: SharedShiftComputed(
          id: "\(sharerId)-shift",
          durationHours: 8,
          paidHours: 8,
          basePay: 0,
          supplementPay: 0,
          gross: 0
        ),
        tax_enabled: nil,
        tax_percentage: nil,
        custom_supplements: nil,
        recurring_id: nil,
        recurring_anchor_weekday: nil
      ),
      status: status,
      showEarnings: false,
      currency: nil
    )
  }
}
