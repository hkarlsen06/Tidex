import SwiftUI
import UIKit
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

  func testCalendarContentColorStyleOnlyUsesWorkplaceColorsForWorkplaceMode() {
    XCTAssertTrue(CalendarContentColorStyle.workplace.usesWorkplaceColors)
    XCTAssertFalse(CalendarContentColorStyle.monochrome.usesWorkplaceColors)
  }
}

final class SemanticColorContrastTests: XCTestCase {
  private static let minimumTextContrast = 4.5
  private static let minimumNonTextContrast = 3.0

  func testSemanticTextColorsMeetWCAGAAContrast() {
    let pairs = [
      ContrastPair(foreground: "TidexTextPrimary", background: "TidexBackground"),
      ContrastPair(foreground: "TidexTextPrimary", background: "TidexSurfacePrimary"),
      ContrastPair(foreground: "TidexTextSecondary", background: "TidexSurfacePrimary"),
      ContrastPair(foreground: "TidexTextMuted", background: "TidexSurfacePrimary"),
      ContrastPair(foreground: "TidexTextPrimary", background: "TidexSurfaceSecondary"),
      ContrastPair(foreground: "TidexTextSecondary", background: "TidexBackground"),
      ContrastPair(foreground: "TidexTextSecondary", background: "TidexSurfaceSecondary"),
      ContrastPair(foreground: "TidexTextMuted", background: "TidexBackground"),
      ContrastPair(foreground: "TidexTextMuted", background: "TidexSurfaceSecondary"),
      ContrastPair(foreground: "TidexTextOnBrand", background: "TidexBlue"),
      ContrastPair(foreground: "TidexTextOnBrand", background: "TidexBrandPrimary"),
      ContrastPair(foreground: "TidexTextOnWarning", background: "TidexWarning"),
      ContrastPair(foreground: "TidexTextOnDanger", background: "TidexError"),
      ContrastPair(foreground: "TidexTextOnSuccess", background: "TidexSuccess"),
    ]
    // Blue, status and purple colors drawn as text or icons on the three surfaces.
    let coloredTextPairs = ["TidexBlueText", "TidexError", "TidexSuccess", "TidexWarning", "TidexPurple"]
      .flatMap { foreground in
        ["TidexBackground", "TidexSurfacePrimary", "TidexSurfaceSecondary"].map {
          ContrastPair(foreground: foreground, background: $0)
        }
      }

    assertContrast(
      pairs + coloredTextPairs,
      minimumRatio: Self.minimumTextContrast
    )
  }

  /// Increase Contrast variants must stay readable, and the text ones must reach 7:1.
  func testIncreaseContrastVariantsMeetEnhancedContrast() {
    let surfaces = ["TidexBackground", "TidexSurfacePrimary", "TidexSurfaceSecondary"]
    let textPairs = ["TidexTextSecondary", "TidexTextMuted", "TidexBlueText"].flatMap { foreground in
      surfaces.map { ContrastPair(foreground: foreground, background: $0) }
    }
    let borderPairs = surfaces.map { ContrastPair(foreground: "TidexBorder", background: $0) }

    assertContrast(textPairs, minimumRatio: 7.0, contrast: .high)
    assertContrast(borderPairs, minimumRatio: 4.5, contrast: .high)
  }

  func testSurfaceBoundaryColorsMeetWCAGNonTextContrast() {
    let pairs = [
      ContrastPair(foreground: "TidexBorder", background: "TidexBackground"),
      ContrastPair(foreground: "TidexBorder", background: "TidexSurfacePrimary"),
      ContrastPair(foreground: "TidexBorder", background: "TidexSurfaceSecondary"),
      ContrastPair(foreground: "TidexBorderSubtle", background: "TidexBackground"),
      ContrastPair(foreground: "TidexBorderSubtle", background: "TidexSurfacePrimary"),
      ContrastPair(foreground: "TidexBorderSubtle", background: "TidexSurfaceSecondary"),
    ]

    assertContrast(
      pairs,
      minimumRatio: Self.minimumNonTextContrast
    )
  }

  /// WorkplaceNameText draws badge text in white or black, whichever contrasts more.
  func testWorkplacePaletteBadgesHaveReadableWhiteOrBlackText() {
    for hex in WorkplaceColor.curatedHexPalette {
      guard let badge = WorkplaceColor.hexToUIColor(hex) else {
        XCTFail("Invalid palette color \(hex)")
        continue
      }
      let best = max(badge.contrastRatio(against: .white), badge.contrastRatio(against: .black))

      XCTAssertGreaterThanOrEqual(best, Self.minimumTextContrast, "\(hex) badge text contrast \(best)")
    }
  }

  private func assertContrast(
    _ pairs: [ContrastPair],
    minimumRatio: Double,
    contrast: UIAccessibilityContrast = .normal
  ) {
    for colorScheme in [UIUserInterfaceStyle.light, .dark] {
      let traitCollection = UITraitCollection { traits in
        traits.userInterfaceStyle = colorScheme
        traits.accessibilityContrast = contrast
      }

      for pair in pairs {
        let foreground = resolvedColor(named: pair.foreground, compatibleWith: traitCollection)
        let background = resolvedColor(named: pair.background, compatibleWith: traitCollection)
        let ratio = foreground.contrastRatio(against: background)

        let contrastName = contrast == .high ? "high" : "normal"

        XCTAssertGreaterThanOrEqual(
          ratio,
          minimumRatio,
          "\(pair.foreground) on \(pair.background) in \(colorScheme.name) mode "
            + "(\(contrastName) contrast) has contrast \(ratio)"
        )
      }
    }
  }

  private func resolvedColor(named name: String, compatibleWith traits: UITraitCollection)
    -> UIColor
  {
    guard
      let color = UIColor(named: name, in: Bundle(for: AppDelegate.self), compatibleWith: traits)
    else {
      XCTFail("Missing semantic color asset named \(name)")
      return .clear
    }

    return color.resolvedColor(with: traits)
  }
}

@MainActor
final class PrimaryButtonLayoutTests: XCTestCase {
  func testLargeTextExpandsButtonAndLoadingPreservesItsSize() {
    let title = "Continue with your account"
    let availableSize = CGSize(width: 280, height: 1_000)
    let idle = UIHostingController(
      rootView: PrimaryButton(title: title, action: {})
        .environment(\.dynamicTypeSize, .accessibility3)
    )
    let loading = UIHostingController(
      rootView: PrimaryButton(title: title, action: {}, isLoading: true)
        .environment(\.dynamicTypeSize, .accessibility3)
    )
    let idleSize = idle.sizeThatFits(in: availableSize)
    let loadingSize = loading.sizeThatFits(in: availableSize)

    XCTAssertGreaterThan(idleSize.height, Spacing.buttonHeight)
    XCTAssertEqual(idleSize.height, loadingSize.height, accuracy: 0.5)
    XCTAssertEqual(idleSize.width, loadingSize.width, accuracy: 0.5)
  }
}

@MainActor
final class ShiftCardLayoutTests: XCTestCase {
  func testLargeTextStacksDetailsWithinTheAvailableWidth() {
    let card = ShiftCardContentLayout {
      Text("Next payout")
    } leadingBottom: {
      Text("Tuesday, September 15")
    } trailingTop: {
      Text("24 380 kr")
    } trailingBottom: {
      Text("In 9 days")
    }
    .font(.body)
    .environment(\.dynamicTypeSize, .accessibility3)
    let host = UIHostingController(rootView: card)
    let size = host.sizeThatFits(in: CGSize(width: 280, height: 1_000))

    XCTAssertLessThanOrEqual(size.width, 280)
    XCTAssertGreaterThan(size.height, ShiftCardMetrics.regularCardMinHeight)
  }
}

private struct ContrastPair {
  let foreground: String
  let background: String
}

extension UIUserInterfaceStyle {
  fileprivate var name: String {
    switch self {
    case .dark:
      return "dark"

    case .light:
      return "light"

    case .unspecified:
      return "unspecified"

    @unknown default:
      return "unknown"
    }
  }
}

extension UIColor {
  fileprivate func contrastRatio(against other: UIColor) -> Double {
    let firstLuminance = relativeLuminance
    let secondLuminance = other.relativeLuminance
    let lighter = max(firstLuminance, secondLuminance)
    let darker = min(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private var relativeLuminance: Double {
    let components = rgbaComponents
    let red = Self.linearizedSRGBComponent(components.red)
    let green = Self.linearizedSRGBComponent(components.green)
    let blue = Self.linearizedSRGBComponent(components.blue)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }

  private var rgbaComponents: (red: Double, green: Double, blue: Double, alpha: Double) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (Double(red), Double(green), Double(blue), Double(alpha))
  }

  private static func linearizedSRGBComponent(_ component: Double) -> Double {
    if component <= 0.04045 {
      return component / 12.92
    }

    return pow((component + 0.055) / 1.055, 2.4)
  }
}
