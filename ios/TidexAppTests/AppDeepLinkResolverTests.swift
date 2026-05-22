import XCTest

@testable import Tidex

final class AppDeepLinkResolverTests: XCTestCase {
  func testResolvesSettingsPayDeepLinkWithJobId() throws {
    let url = try XCTUnwrap(URL(string: "tidex://settings/pay?jobId=job_123"))

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .pay(jobId: "job_123")))
  }

  func testResolvesSettingsPayDeepLinkWithoutJobId() throws {
    let url = try XCTUnwrap(URL(string: "tidex://settings/pay"))

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .pay(jobId: nil)))
  }

  func testResolvesHttpsSettingsAlias() throws {
    let url = try XCTUnwrap(URL(string: "https://app.tidex.no/no/settings/recurring-shifts"))

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .recurringShifts))
  }

  func testResolvesShiftHighlightDeepLinkWithShiftIds() throws {
    let url = try XCTUnwrap(
      URL(string: "tidex://shifts?dates=2026-06-01,2026-06-02&shiftIds=a,b&action=highlight")
    )

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(
      deepLink,
      .shifts(
        dates: ["2026-06-01", "2026-06-02"],
        shiftIds: ["a", "b"],
        action: .highlight
      )
    )
  }

  func testResolvesAddShiftDeepLinkWithRecurringMode() throws {
    let url = try XCTUnwrap(URL(string: "tidex://add-shift?mode=recurring"))

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .addShift(mode: .recurring))
  }

  func testResolvesHttpsAddShiftDeepLinkWithEventsMode() throws {
    let url = try XCTUnwrap(URL(string: "https://app.tidex.no/no/add-shift?mode=events"))

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .addShift(mode: .events))
  }

  func testResolvesAdminSettingsDeepLinkToAdminPanel() throws {
    let url = try XCTUnwrap(URL(string: "tidex://settings/admin"))

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .settings(destination: .admin))
  }

  func testResolvesHttpsSettingsAdminReportsToAdminReport() throws {
    let url = try XCTUnwrap(
      URL(string: "https://app.tidex.no/settings/admin?tab=reports&reportId=report_123")
    )

    let deepLink = AppDeepLinkResolver.resolve(url)

    XCTAssertEqual(deepLink, .adminReport(reportId: "report_123"))
  }
}
