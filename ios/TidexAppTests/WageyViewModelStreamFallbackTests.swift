import XCTest

@testable import Tidex

final class WageyViewModelStreamFallbackTests: XCTestCase {
  func testReturnsInlineErrorMessageForFailedEmptyStream() {
    let message = WageyViewModel.fallbackAssistantMessage(
      error: WageyServiceError.streamError(message: "No response from AI provider"),
      limitReached: false,
      wasCancelled: false,
      hasAssistantContent: false
    )

    XCTAssertEqual(message, "Stream error: No response from AI provider")
  }

  func testReturnsGenericFallbackForEmptySuccessfulStream() {
    let message = WageyViewModel.fallbackAssistantMessage(
      error: nil,
      limitReached: false,
      wasCancelled: false,
      hasAssistantContent: false
    )

    XCTAssertEqual(message, String(localized: .wageyErrorUnknown))
  }

  func testDoesNotReturnFallbackWhenStreamWasCancelled() {
    let message = WageyViewModel.fallbackAssistantMessage(
      error: WageyServiceError.cancelled,
      limitReached: false,
      wasCancelled: true,
      hasAssistantContent: false
    )

    XCTAssertNil(message)
  }

  func testDoesNotReturnFallbackWhenAssistantAlreadyHasContent() {
    let message = WageyViewModel.fallbackAssistantMessage(
      error: WageyServiceError.streamError(message: "No response from AI provider"),
      limitReached: false,
      wasCancelled: false,
      hasAssistantContent: true
    )

    XCTAssertNil(message)
  }

  func testDoesNotReturnFallbackWhenLimitReached() {
    let message = WageyViewModel.fallbackAssistantMessage(
      error: WageyError.noAccess,
      limitReached: true,
      wasCancelled: false,
      hasAssistantContent: false
    )

    XCTAssertNil(message)
  }
}
