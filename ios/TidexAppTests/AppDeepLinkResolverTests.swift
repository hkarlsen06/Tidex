import XCTest

@testable import Tidex

internal final class AppDeepLinkResolverTests: XCTestCase {
  internal func testResolvesSettingsPayDeepLinkWithJobId() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/pay?jobId=job_123"))

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .pay(jobId: "job_123")))
  }

  internal func testResolvesSettingsPayDeepLinkWithoutJobId() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/pay"))

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .pay(jobId: nil)))
  }

  internal func testResolvesSettingsRecurringShiftsDeepLink() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/recurring-shifts"))

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .recurringShifts))
  }

  internal func testResolvesShiftHighlightDeepLinkWithShiftIds() throws {
    let url: URL = try XCTUnwrap(
      URL(string: "tidex://shifts?dates=2026-06-01,2026-06-02&shiftIds=a,b&action=highlight")
    )

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(
      deepLink,
      .shifts(
        dates: ["2026-06-01", "2026-06-02"],
        shiftIds: ["a", "b"],
        action: .highlight
      )
    )
  }

  internal func testResolvesAddShiftDeepLinkWithRecurringMode() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://add-shift?mode=recurring"))

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .addShift(mode: .recurring, date: nil))
  }

  internal func testResolvesAddShiftDeepLinkWithDate() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://add?date=2026-09-02"))

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .addShift(mode: nil, date: "2026-09-02"))
  }

  internal func testResolvesAdminSettingsDeepLinkToAdminPanel() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/admin"))

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .admin))
  }

  internal func testInviteLinksResolveToTheInviterInBothForms() throws {
    let inviterId = "0b7e3f2a-5c1d-4e8f-9a6b-2d4c8e1f3a5b"
    for link in [
      "tidex://invite/\(inviterId)",
      "https://tidex.no/invite/\(inviterId)",
      "https://tidex.no/invite/\(inviterId.uppercased())/",
    ] {
      let url: URL = try XCTUnwrap(URL(string: link))
      XCTAssertEqual(AppDeepLinkResolver.resolve(url), .invite(inviterId: inviterId), link)
    }
  }

  internal func testInviteLinksRejectAnythingButOneUserIdOnTidex() throws {
    let inviterId = "0b7e3f2a-5c1d-4e8f-9a6b-2d4c8e1f3a5b"
    for link in [
      "tidex://invite/not-a-uuid",
      "tidex://invite/",
      "tidex://invite/\(inviterId)/extra",
      "https://tidex.no/invite/12345",
      "https://tidex.no/invite/",
      "https://tidex.no/invite/\(inviterId)/extra",
      "https://tidex.no/no/invite/\(inviterId)",
      "http://tidex.no/invite/\(inviterId)",
      "https://evil.example/invite/\(inviterId)",
      "https://tidex.no.evil.example/invite/\(inviterId)",
      "https://app.tidex.no/invite/\(inviterId)",
      "https://app.tidex.no/settings/admin",
    ] {
      let url: URL = try XCTUnwrap(URL(string: link))
      XCTAssertNil(AppDeepLinkResolver.resolve(url), link)
    }
  }

  internal func testNotificationShiftReminderHighlightsShift() {
    let userInfo: [AnyHashable: Any] = [
      "type": "shift_reminder", "shift_date": "2026-06-01", "shift_id": "shift_1",
    ]

    XCTAssertEqual(
      AppDeepLinkResolver.resolve(notificationUserInfo: userInfo),
      .shifts(dates: ["2026-06-01"], shiftIds: ["shift_1"], action: .highlight)
    )
  }

  internal func testNotificationSharedShiftUsesDatesFromChanges() throws {
    let userInfo: [AnyHashable: Any] = [
      "type": "shared_shift_updated",
      "owner_id": "owner_1",
      "shift_dates": "2020-01-01",
      "changes": [
        ["shift_id": "a", "date": "2026-06-02", "op": "updated"],
        ["shift_id": "b", "date": "2026-06-01", "op": "deleted"],
        ["shift_id": "c", "date": "2026-06-01", "op": "added"],
      ],
    ]

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(
      notificationUserInfo: userInfo)

    guard case .sharing(let sharerId, let dates, let changes) = deepLink else {
      return XCTFail("Expected a sharing deep link, got \(String(describing: deepLink))")
    }
    XCTAssertEqual(sharerId, "owner_1")
    XCTAssertEqual(dates?.sorted(), ["2026-06-01", "2026-06-02"])
    XCTAssertEqual(changes?.map(\.shiftId), ["a", "b", "c"])
  }

  internal func testNotificationSharedShiftFallsBackToLegacyDateString() {
    let userInfo: [AnyHashable: Any] = [
      "type": "shared_shift_created", "owner_id": "owner_1",
      "shift_dates": "2026-06-01, 2026-06-02",
    ]

    XCTAssertEqual(
      AppDeepLinkResolver.resolve(notificationUserInfo: userInfo),
      .sharing(sharerId: "owner_1", highlightDates: ["2026-06-01", "2026-06-02"], changes: nil)
    )
  }

  internal func testNotificationTypingOpensChatWithTypingSender() {
    let userInfo: [AnyHashable: Any] = [
      "type": "thread_typing", "thread_id": "thread_1", "sender_user_id": "friend_1",
    ]

    let deepLink: AppCoordinator.DeepLink? = AppDeepLinkResolver.resolve(
      notificationUserInfo: userInfo)

    guard
      case .friendChat(let threadId, let messageId, let senderId, let typingId, let requestId) =
        deepLink
    else {
      return XCTFail("Expected a friend chat deep link, got \(String(describing: deepLink))")
    }
    XCTAssertEqual(threadId, "thread_1")
    XCTAssertNil(messageId)
    XCTAssertEqual(senderId, "friend_1")
    XCTAssertEqual(typingId, "friend_1")
    XCTAssertNotNil(requestId)
  }

  internal func testNotificationDeeplinkResolvesOnlyTidexURLs() {
    XCTAssertEqual(
      AppDeepLinkResolver.resolve(notificationUserInfo: [
        "type": "admin_broadcast", "deeplink": "tidex://settings/pay",
      ]),
      .settings(destination: .pay(jobId: nil))
    )
    // The app delegate opens other schemes in the system instead.
    XCTAssertNil(
      AppDeepLinkResolver.resolve(notificationUserInfo: [
        "type": "admin_broadcast", "deeplink": "itms-apps://apps.apple.com/app/id1",
      ])
    )
  }

  internal func testNotificationSmartPromptWithoutDateFallsThroughToDeeplink() {
    let userInfo: [AnyHashable: Any] = ["type": "smart_prompt", "deeplink": "tidex://add"]

    XCTAssertEqual(
      AppDeepLinkResolver.resolve(notificationUserInfo: userInfo),
      .addShift(mode: nil, date: nil)
    )
  }

  internal func testStartupTabFromRemovedAddTabFallsBackToHome() {
    // Add is a sheet now, so users who picked it as their startup tab land on Home.
    XCTAssertEqual(MainTabView.Tab.startupTab(rawValue: "add"), .home)
    XCTAssertEqual(MainTabView.Tab.startupTab(rawValue: nil), .home)
    XCTAssertEqual(MainTabView.Tab.startupTab(rawValue: "shifts"), .shifts)
    XCTAssertEqual(MainTabView.Tab.startupTab(rawValue: "stats"), .stats)
    // Friends keeps the stored "sharing" value that settings sync and onboarding write.
    XCTAssertEqual(MainTabView.Tab.startupTab(rawValue: "sharing"), .friends)
    XCTAssertNil(StartupTabOption(rawValue: "add"))
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
