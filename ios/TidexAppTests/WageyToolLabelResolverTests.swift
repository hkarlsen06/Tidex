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

  func testManagePayrollAdjustmentUsesLocalizedLabels() {
    let fallbackCall = ToolCall(
      id: "tool-7",
      name: "manage_payroll_adjustment"
    )
    let createCall = ToolCall(
      id: "tool-8",
      name: "manage_payroll_adjustment",
      arguments: #"{"action":"create"}"#
    )
    let deleteCall = ToolCall(
      id: "tool-9",
      name: "manage_payroll_adjustment",
      arguments: #"{"action":"delete"}"#
    )

    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: fallbackCall, isExecuting: true),
      String(localized: .wageyToolManagePayrollAdjustment)
    )
    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: createCall, isExecuting: true),
      String(localized: .wageyToolPayrollAdjustmentCreating)
    )
    XCTAssertEqual(
      WageyToolLabelResolver.displayName(for: deleteCall, isExecuting: true),
      String(localized: .wageyToolPayrollAdjustmentDeleting)
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
