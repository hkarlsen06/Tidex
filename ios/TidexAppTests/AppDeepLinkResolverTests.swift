import XCTest

@testable import Tidex

internal final class AppDeepLinkResolverTests: XCTestCase {
  internal func testResolvesSettingsPayDeepLinkWithJobId() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/pay?jobId=job_123"))

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .pay(jobId: "job_123")))
  }

  internal func testResolvesSettingsPayDeepLinkWithoutJobId() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/pay"))

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .pay(jobId: nil)))
  }

  internal func testResolvesSettingsRecurringShiftsDeepLink() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/recurring-shifts"))

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .recurringShifts))
  }

  internal func testResolvesHttpsSettingsAlias() throws {
    let url: URL = try XCTUnwrap(URL(string: "https://app.tidex.no/no/settings/recurring-shifts"))

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .recurringShifts))
  }

  internal func testResolvesShiftHighlightDeepLinkWithShiftIds() throws {
    let url: URL = try XCTUnwrap(
      URL(string: "tidex://shifts?dates=2026-06-01,2026-06-02&shiftIds=a,b&action=highlight")
    )

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

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

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .addShift(mode: .recurring, date: nil))
  }

  internal func testResolvesHttpsAddShiftDeepLinkWithEventsMode() throws {
    let url: URL = try XCTUnwrap(URL(string: "https://app.tidex.no/no/add-shift?mode=events"))

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .addShift(mode: .events, date: nil))
  }

  internal func testResolvesAddShiftDeepLinkWithDate() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://add?date=2026-09-02"))

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .addShift(mode: nil, date: "2026-09-02"))
  }

  internal func testResolvesAdminSettingsDeepLinkToAdminPanel() throws {
    let url: URL = try XCTUnwrap(URL(string: "tidex://settings/admin"))

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .admin))
  }

  internal func testResolvesHttpsSettingsAdminReportsToAdminReport() throws {
    let url: URL = try XCTUnwrap(
      URL(string: "https://app.tidex.no/settings/admin?tab=reports&reportId=report_123")
    )

    let deepLink: AppDeepLink? = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .adminReport(reportId: "report_123"))
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
