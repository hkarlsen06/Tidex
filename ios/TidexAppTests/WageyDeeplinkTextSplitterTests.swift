import XCTest

@testable import Tidex

final class WageyDeeplinkTextSplitterTests: XCTestCase {
  func testSplitsTidexMarkdownDeeplinkOutOfText() throws {
    let segments = WageyDeeplinkTextSplitter.split(
      "Ferdig. [Åpne lønn](tidex://settings/pay?jobId=job_123) Sjekk at alt stemmer."
    )

    XCTAssertEqual(
      segments,
      [
        .text("Ferdig."),
        .deeplink(
          title: "Åpne lønn",
          url: try XCTUnwrap(URL(string: "tidex://settings/pay?jobId=job_123"))
        ),
        .text("Sjekk at alt stemmer."),
      ]
    )
  }

  func testSplitsUniversalLinkDeeplink() throws {
    let segments = WageyDeeplinkTextSplitter.split(
      "[Vis vakten](https://app.tidex.no/shifts?dates=2026-06-01&shiftIds=abc&action=highlight)"
    )

    XCTAssertEqual(
      segments,
      [
        .deeplink(
          title: "Vis vakten",
          url: try XCTUnwrap(
            URL(
              string:
                "https://app.tidex.no/shifts?dates=2026-06-01&shiftIds=abc&action=highlight"
            )
          )
        )
      ]
    )
  }

  func testLeavesExternalMarkdownLinksInline() {
    let text = "Les [kilden](https://example.com) først."

    XCTAssertEqual(WageyDeeplinkTextSplitter.split(text), [.text(text)])
  }

  func testDetectsOnlyTidexDeeplinks() {
    XCTAssertTrue(
      WageyDeeplinkTextSplitter.containsDeeplink(
        in: "Åpne [faste vakter](tidex://settings/recurring-shifts)."
      )
    )
    XCTAssertFalse(
      WageyDeeplinkTextSplitter.containsDeeplink(in: "Les [hjelpen](https://example.com).")
    )
  }
}
