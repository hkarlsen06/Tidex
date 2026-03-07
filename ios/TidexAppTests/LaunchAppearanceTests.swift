import SwiftUI
import XCTest

@testable import Tidex

final class LaunchAppearanceTests: XCTestCase {
  func testResolvedColorSchemeUsesSystemSchemeWhenThemeIsSystem() {
    XCTAssertEqual(AppTheme.system.resolvedColorScheme(fallback: .light), .light)
    XCTAssertEqual(AppTheme.system.resolvedColorScheme(fallback: .dark), .dark)
  }

  func testResolvedColorSchemeIgnoresSystemSchemeWhenThemeIsLight() {
    XCTAssertEqual(AppTheme.light.resolvedColorScheme(fallback: .dark), .light)
  }

  func testResolvedColorSchemeIgnoresSystemSchemeWhenThemeIsDark() {
    XCTAssertEqual(AppTheme.dark.resolvedColorScheme(fallback: .light), .dark)
  }
}
