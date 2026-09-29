// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable closure_body_length conditional_returns_on_newline explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface file_types_order implicit_optional_initialization multiline_arguments_brackets
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers type_contents_order
import SwiftUI
import UIKit

/// Renders workplace names with adaptive contrast.
/// Always renders a rounded color badge when a workplace or fallback color is available.
struct WorkplaceNameText: View {
  let name: String
  let colorHex: String?
  var font: Font = .tidexBody
  var fallbackBadgeColor: Color?
  var lineLimit: Int? = 1
  var maxTextWidth: CGFloat?
  var maxTextAlignment: Alignment = .leading
  var multilineTextAlignment: TextAlignment = .leading
  var badgeCornerRadius: CGFloat = CornerRadius.sm
  var badgeHorizontalPadding: CGFloat = Spacing.xs
  var badgeVerticalPadding: CGFloat = Spacing.xxxs
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// A workplace name is essential text, so it wraps instead of truncating at accessibility sizes.
  private var effectiveLineLimit: Int? {
    dynamicTypeSize.isAccessibilitySize ? nil : lineLimit
  }

  var body: some View {
    if let badgeColor = resolvedBadgeColor {
      Text(name)
        .font(font)
        .foregroundColor(badgeForegroundColor(for: badgeColor))
        .multilineTextAlignment(multilineTextAlignment)
        .lineLimit(effectiveLineLimit)
        .truncationMode(.tail)
        .padding(.horizontal, badgeHorizontalPadding)
        .padding(.vertical, badgeVerticalPadding)
        .background(
          RoundedRectangle(cornerRadius: badgeCornerRadius, style: .continuous)
            .fill(Color(uiColor: badgeColor))
        )
        .frame(maxWidth: maxTextWidth, alignment: maxTextAlignment)
    } else {
      Text(name)
        .font(font)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(multilineTextAlignment)
        .lineLimit(effectiveLineLimit)
        .truncationMode(.tail)
        .frame(maxWidth: maxTextWidth, alignment: maxTextAlignment)
    }
  }

  private var resolvedBadgeColor: UIColor? {
    if let parsed = WorkplaceColor.hexToUIColor(colorHex) {
      return parsed
    }
    if let fallbackBadgeColor {
      return UIColor(fallbackBadgeColor)
    }
    return nil
  }

  private func badgeForegroundColor(for badgeColor: UIColor) -> Color {
    let resolvedColor = badgeColor.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: userInterfaceStyle))
    let luminance = Self.relativeLuminance(for: resolvedColor)
    // Pure black, not tidexLightTextPrimary: only white-or-black keeps every curated color at 4.5:1.
    return Self.contrastRatio(luminance, 1) >= Self.contrastRatio(luminance, 0)
      ? .tidexTextOnBrand : .black
  }

  private var userInterfaceStyle: UIUserInterfaceStyle {
    colorScheme == .dark ? .dark : .light
  }

  private static func contrastRatio(_ firstLuminance: CGFloat, _ secondLuminance: CGFloat)
    -> CGFloat
  {
    (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
  }

  private static func relativeLuminance(for color: UIColor) -> CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return 0
    }

    return 0.2126 * linearizedSRGB(red)
      + 0.7152 * linearizedSRGB(green)
      + 0.0722 * linearizedSRGB(blue)
  }

  private static func linearizedSRGB(_ component: CGFloat) -> CGFloat {
    component <= 0.03928
      ? component / 12.92
      : pow((component + 0.055) / 1.055, 2.4)
  }
}

/// Horizontal curated color picker for workplace colors.
struct WorkplaceColorCarousel: View {
  let selectedHex: String?
  let onSelect: (String) -> Void

  private static let swatchControlSize: CGFloat = 44
  private static let swatchSize: CGFloat = 32
  private static let selectedRingSize: CGFloat = 36

  private var normalizedSelectedHex: String? {
    guard var selectedHex else { return nil }
    selectedHex = selectedHex.trimmingCharacters(in: .whitespacesAndNewlines)
    if selectedHex.hasPrefix("#") {
      selectedHex.removeFirst()
    }
    guard selectedHex.count == 6 else { return nil }
    return "#\(selectedHex.uppercased())"
  }

  private var selectedSwatchColor: Color? {
    guard
      let normalizedSelectedHex,
      let uiColor = WorkplaceColor.hexToUIColor(normalizedSelectedHex)
    else {
      return nil
    }
    return Color(uiColor: uiColor)
  }

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Group {
        if let selectedSwatchColor {
          ZStack {
            Circle()
              .fill(selectedSwatchColor)
              .frame(width: Self.swatchSize, height: Self.swatchSize)

            selectedRing

            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(swatchForegroundColor(for: normalizedSelectedHex))
          }
        } else {
          Circle()
            .stroke(Color.tidexBorder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: Self.swatchSize, height: Self.swatchSize)
        }
      }
      .frame(width: Self.swatchControlSize, height: Self.swatchControlSize)
      .accessibilityHidden(true)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.xs) {
          ForEach(WorkplaceColor.curatedHexPalette, id: \.self) { hex in
            let swatchColor = Color(uiColor: WorkplaceColor.hexToUIColor(hex) ?? .systemBlue)
            let isSelected = normalizedSelectedHex == hex

            Button {
              onSelect(hex)
            } label: {
              ZStack {
                Circle()
                  .fill(swatchColor)
                  .frame(width: Self.swatchSize, height: Self.swatchSize)

                if isSelected {
                  selectedRing

                  Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(swatchForegroundColor(for: hex))
                }
              }
              .frame(width: Self.swatchControlSize, height: Self.swatchControlSize)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WorkplaceColor.accessibilityName(for: hex))
            .accessibilityInputLabels([WorkplaceColor.accessibilityName(for: hex)])
            .accessibilityAddTraits(isSelected ? .isSelected : [])
          }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 1)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(.settingsPayAddJobColorLabel))
  }

  private var selectedRing: some View {
    Circle()
      .stroke(Color.tidexSurfacePrimary.opacity(0.98), lineWidth: 2)
      .frame(width: Self.selectedRingSize, height: Self.selectedRingSize)
      .overlay {
        Circle()
          .stroke(Color.tidexTextPrimary.opacity(0.28), lineWidth: 1)
          .frame(width: Self.selectedRingSize, height: Self.selectedRingSize)
      }
  }

  private func swatchForegroundColor(for hex: String?) -> Color {
    guard
      let uiColor = WorkplaceColor.hexToUIColor(hex),
      WorkplaceColor.relativeLuminance(for: uiColor) > 0.42
    else {
      return .tidexTextOnBrand
    }

    return .tidexLightTextPrimary
  }
}

enum WorkplaceColor {
  // Curated workplace palette (popular hues first). Grayscale colors are intentionally excluded.
  static let curatedHexPalette: [String] = [
    "#3B82F6",
    "#22C55E",
    "#EF4444",
    "#F59E0B",
    "#A855F7",
    "#14B8A6",
    "#EC4899",
    "#06B6D4",
    "#6366F1",
    "#8B5CF6",
    "#10B981",
    "#84CC16",
    "#F97316",
    "#EAB308",
    "#F43F5E",
    "#D946EF",
    "#0EA5E9",
    "#2563EB",
    "#16A34A",
    "#DC2626",
    "#EA580C",
    "#7C3AED",
    "#0891B2",
    "#BE123C",
  ]

  /// Spoken names of the curated swatches. Voice Control needs distinct names, so hex codes won't do.
  private static let swatchNames: [String: LocalizedStringResource] = [
    "#3B82F6": .commonAccessibilityColorBlue,
    "#22C55E": .commonAccessibilityColorGreen,
    "#EF4444": .commonAccessibilityColorRed,
    "#F59E0B": .commonAccessibilityColorAmber,
    "#A855F7": .commonAccessibilityColorPurple,
    "#14B8A6": .commonAccessibilityColorTeal,
    "#EC4899": .commonAccessibilityColorPink,
    "#06B6D4": .commonAccessibilityColorCyan,
    "#6366F1": .commonAccessibilityColorIndigo,
    "#8B5CF6": .commonAccessibilityColorViolet,
    "#10B981": .commonAccessibilityColorEmerald,
    "#84CC16": .commonAccessibilityColorLime,
    "#F97316": .commonAccessibilityColorOrange,
    "#EAB308": .commonAccessibilityColorYellow,
    "#F43F5E": .commonAccessibilityColorRose,
    "#D946EF": .commonAccessibilityColorFuchsia,
    "#0EA5E9": .commonAccessibilityColorSkyBlue,
    "#2563EB": .commonAccessibilityColorRoyalBlue,
    "#16A34A": .commonAccessibilityColorForestGreen,
    "#DC2626": .commonAccessibilityColorDarkRed,
    "#EA580C": .commonAccessibilityColorBurntOrange,
    "#7C3AED": .commonAccessibilityColorDeepViolet,
    "#0891B2": .commonAccessibilityColorDarkCyan,
    "#BE123C": .commonAccessibilityColorCrimson,
  ]

  static func accessibilityName(for hex: String) -> Text {
    guard let name = swatchNames[hex.uppercased()] else { return Text(verbatim: hex) }
    return Text(name)
  }

  static func hexToUIColor(_ hex: String?) -> UIColor? {
    guard var hex else { return nil }
    hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") {
      hex.removeFirst()
    }
    guard hex.count == 6, let value = Int(hex, radix: 16) else {
      return nil
    }

    let red = CGFloat((value >> 16) & 0xFF) / 255
    let green = CGFloat((value >> 8) & 0xFF) / 255
    let blue = CGFloat(value & 0xFF) / 255
    return UIColor(red: red, green: green, blue: blue, alpha: 1)
  }

  static func relativeLuminance(for color: UIColor) -> CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return 0
    }

    return 0.2126 * linearizedSRGB(red)
      + 0.7152 * linearizedSRGB(green)
      + 0.0722 * linearizedSRGB(blue)
  }

  private static func linearizedSRGB(_ component: CGFloat) -> CGFloat {
    component <= 0.03928
      ? component / 12.92
      : pow((component + 0.055) / 1.055, 2.4)
  }
}
