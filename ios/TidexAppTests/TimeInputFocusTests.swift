import SwiftUI
import UIKit
import XCTest

@testable import Tidex

@MainActor
final class TimeInputFocusTests: XCTestCase {
  func testFocusTransferWaitsForDestinationToJoinTheWindow() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previousWindow = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    let start = UITextField(frame: CGRect(x: 20, y: 100, width: 120, height: 40))
    let end = UITextField(frame: CGRect(x: 160, y: 100, width: 120, height: 40))
    start.keyboardType = .numberPad
    end.keyboardType = .numberPad
    window.addSubview(start)
    window.makeKeyAndVisible()
    defer {
      window.endEditing(true)
      window.isHidden = true
      previousWindow?.makeKey()
    }
    let focus = TimeInputFocusController()
    focus.register(start, field: .start)
    focus.register(end, field: .end)
    let keyboardShown = expectation(
      forNotification: UIResponder.keyboardDidShowNotification, object: nil)
    focus.focus(.start)
    await fulfillment(of: [keyboardShown], timeout: 5)

    // SwiftUI can register a replacement field before attaching it to the window.
    focus.focus(.end)
    XCTAssertTrue(
      start.isFirstResponder, "Keep the keyboard until the destination can accept focus")
    window.addSubview(end)
    focus.focus(.end)
    XCTAssertTrue(end.isFirstResponder)
    XCTAssertFalse(start.isFirstResponder)
  }

  func testAutoAdvanceKeepsKeyboardVisibleInHorizontalLayout() async throws {
    try await checkAutoAdvance(width: 360, dynamicTypeSize: .large)
  }

  func testAutoAdvanceKeepsKeyboardVisibleInAccessibilityLayout() async throws {
    try await checkAutoAdvance(width: 300, dynamicTypeSize: .accessibility3)
  }

  private func checkAutoAdvance(width: CGFloat, dynamicTypeSize: DynamicTypeSize) async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previousWindow = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    let host = UIHostingController(
      rootView: TimeInputFixture()
        .frame(width: width)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, Locale(identifier: "en_US"))
    )
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.endEditing(true)
      window.isHidden = true
      previousWindow?.makeKey()
    }
    host.view.layoutIfNeeded()
    let fieldsReady = expectation(
      for: NSPredicate { _, _ in
        MainActor.assumeIsolated { self.textFields(in: host.view).count >= 2 }
      }, evaluatedWith: nil)
    await fulfillment(of: [fieldsReady], timeout: 5)
    let fields = textFields(in: host.view)
    let start = try XCTUnwrap(
      fields.first { $0.accessibilityLabel == String(localized: .commonStart) })
    let end = try XCTUnwrap(fields.first { $0.accessibilityLabel == String(localized: .commonEnd) })
    try await checkKeyboardHandoff(start: start, end: end)
  }

  private func checkKeyboardHandoff(start: UITextField, end: UITextField) async throws {
    let keyboardShown = expectation(
      forNotification: UIResponder.keyboardDidShowNotification, object: nil)
    XCTAssertTrue(start.becomeFirstResponder())
    await fulfillment(of: [keyboardShown], timeout: 5)
    XCTAssertTrue(start.isFirstResponder)

    let keyboardHidden = expectation(description: "Keyboard stays visible during auto-advance")
    keyboardHidden.isInverted = true
    let observer = NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
    ) { _ in keyboardHidden.fulfill() }
    enter("0900", in: start)
    XCTAssertEqual(start.text, "09:00")
    XCTAssertTrue(
      end.isFirstResponder, "Auto-advance must transfer focus directly to the visible end field")
    await fulfillment(of: [keyboardHidden], timeout: 0.5)
    NotificationCenter.default.removeObserver(observer)
    XCTAssertTrue(end.isFirstResponder)

    let keyboardDismissed = expectation(
      forNotification: UIResponder.keyboardDidHideNotification, object: nil)
    enter("1700", in: end)
    XCTAssertEqual(end.text, "17:00")
    await fulfillment(of: [keyboardDismissed], timeout: 5)
    XCTAssertFalse(start.isFirstResponder)
    XCTAssertFalse(end.isFirstResponder)
  }

  private func enter(_ digits: String, in field: UITextField) {
    // Deliver the keyboard's editing callback; programmatic insertText bypasses the delegate.
    XCTAssertEqual(
      field.delegate?.textField?(
        field, shouldChangeCharactersIn: NSRange(location: 0, length: 0),
        replacementString: digits), false)
  }

  private func textFields(in view: UIView) -> [UITextField] {
    guard !view.isHidden else { return [] }
    if let field = view as? UITextField { return [field] }
    return view.subviews.flatMap { textFields(in: $0) }
  }
}

private struct TimeInputFixture: View {
  @State private var startTime: Date?
  @State private var endTime: Date?
  @State private var focusedField: TimeInputField?

  var body: some View {
    TimeRangePicker(
      startTime: $startTime,
      endTime: $endTime,
      focusedFieldBinding: $focusedField,
      showsRecentTimeChips: false
    )
  }
}
