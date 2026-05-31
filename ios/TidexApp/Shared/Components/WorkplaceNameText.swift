import SwiftUI
import UIKit

/// Renders workplace names with adaptive contrast.
/// Always renders a rounded color badge when a workplace or fallback color is available.
struct WorkplaceNameText: View {
  let name: String
  let colorHex: String?
  var font: Font = .tidexBody
  var fallbackBadgeColor: Color? = nil
  var lineLimit: Int? = 1
  var maxTextWidth: CGFloat?
  var maxTextAlignment: Alignment = .leading
  var multilineTextAlignment: TextAlignment = .leading
  var badgeCornerRadius: CGFloat = CornerRadius.sm
  var badgeHorizontalPadding: CGFloat = Spacing.xs
  var badgeVerticalPadding: CGFloat = Spacing.xxxs
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    if let badgeColor = resolvedBadgeColor {
      Text(name)
        .font(font)
        .foregroundColor(badgeForegroundColor(for: badgeColor))
        .multilineTextAlignment(multilineTextAlignment)
        .lineLimit(lineLimit)
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
        .lineLimit(lineLimit)
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
    let contrastWithWhite = Self.contrastRatio(luminance, 1)
    let contrastWithBlack = Self.contrastRatio(luminance, 0)

    if Self.shouldPreferWhiteBadgeText(for: resolvedColor, contrastWithWhite: contrastWithWhite) {
      return .tidexTextOnBrand
    }

    return contrastWithWhite >= contrastWithBlack ? .tidexTextOnBrand : .tidexLightTextPrimary
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

  private static func shouldPreferWhiteBadgeText(
    for color: UIColor,
    contrastWithWhite: CGFloat
  ) -> Bool {
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0

    guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    else {
      return false
    }

    let isRedOrRose = hue <= 0.08 || hue >= 0.88
    let isBlueOrPurple = hue >= 0.55 && hue <= 0.88
    return alpha > 0.1
      && brightness >= 0.35
      && saturation >= 0.45
      && contrastWithWhite >= 2.2
      && (isRedOrRose || isBlueOrPurple)
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
            .accessibilityLabel(Text(String(localized: "settings.pay.add_job.color_label")))
            .accessibilityValue(Text(hex))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
          }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 1)
      }
    }
    .accessibilityElement(children: .contain)
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
