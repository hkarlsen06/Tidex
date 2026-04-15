import XCTest

@testable import Tidex

final class WageyToolLabelResolverTests: XCTestCase {
  func testQueryEventsUsesLocalizedFallbackLabel() {
    let toolCall = ToolCall(
      id: "tool-1",
      name: "query_events"
    )

    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: toolCall, isExecuting: true),
      String(localized: .wageyToolQueryEvents)
    )
  }

  func testManageEventUsesActionSpecificLabels() {
    let createCall = ToolCall(
      id: "tool-2",
      name: "manage_event",
      arguments: #"{"action":"create"}"#
    )
    let updateCall = ToolCall(
      id: "tool-3",
      name: "manage_event",
      arguments: #"{"action":"update"}"#
    )
    let deleteCall = ToolCall(
      id: "tool-4",
      name: "manage_event",
      arguments: #"{"action":"delete"}"#
    )

    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: createCall, isExecuting: true),
      String(localized: .wageyToolEventCreating)
    )
    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: updateCall, isExecuting: true),
      String(localized: .wageyToolEventUpdating)
    )
    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: deleteCall, isExecuting: true),
      String(localized: .wageyToolEventDeleting)
    )
  }

  func testPlanScheduleUsesLocalizedFallbackLabel() {
    let toolCall = ToolCall(
      id: "tool-5",
      name: "plan_schedule",
      arguments: #"{"action":"agenda"}"#
    )

    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: toolCall, isExecuting: true),
      String(localized: .wageyToolScheduleAgenda)
    )
  }

  func testCompletedLabelsStripTrailingEllipsis() {
    let toolCall = ToolCall(
      id: "tool-6",
      name: "manage_event",
      arguments: #"{"action":"create"}"#,
      result: "{}",
      success: true
    )

    XCTAssertFalse(
      WageyToolLabelResolver.displayName(for: toolCall, isExecuting: false).contains("...")
    )
  }
}
