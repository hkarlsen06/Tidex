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

  func testFlushesStreamingAssistantSegmentWhenThinkingResumesAfterContent() {
    XCTAssertTrue(
      WageyViewModel.shouldFlushStreamingAssistantSegment(
        onThinkingStatus: true,
        activeContentBlocks: [.text("Første melding før ny tenking.")]
      ))
  }

  func testDoesNotFlushStreamingAssistantSegmentForInitialThinkingWithoutContent() {
    XCTAssertFalse(
      WageyViewModel.shouldFlushStreamingAssistantSegment(
        onThinkingStatus: true,
        activeContentBlocks: []
      ))
  }

  func testDoesNotFlushStreamingAssistantSegmentWhenThinkingTurnsOff() {
    XCTAssertFalse(
      WageyViewModel.shouldFlushStreamingAssistantSegment(
        onThinkingStatus: false,
        activeContentBlocks: [.text("Eksisterende innhold")]
      ))
  }

  func testFlushesStreamingAssistantSegmentOnExplicitMessageBreakWhenContentExists() {
    XCTAssertTrue(
      WageyViewModel.shouldFlushStreamingAssistantSegment(
        onMessageBreak: [.text("Første melding.")]
      ))
  }

  func testDoesNotFlushStreamingAssistantSegmentOnExplicitMessageBreakWithoutContent() {
    XCTAssertFalse(
      WageyViewModel.shouldFlushStreamingAssistantSegment(
        onMessageBreak: []
      ))
  }

  func testDoesNotPersistThinkingStatusForTwoSecondsOrShorter() {
    XCTAssertFalse(WageyViewModel.shouldPersistThinkingStatus(durationSeconds: 1))
    XCTAssertFalse(WageyViewModel.shouldPersistThinkingStatus(durationSeconds: 2))
  }

  func testPersistsThinkingStatusAfterTwoSeconds() {
    XCTAssertTrue(WageyViewModel.shouldPersistThinkingStatus(durationSeconds: 3))
  }

  func testRoundsThinkingStatusDuration() {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let now = Date(timeIntervalSince1970: 1_700_000_002.6)

    XCTAssertEqual(WageyViewModel.thinkingStatusDurationSeconds(since: startedAt, now: now), 3)
  }
}
