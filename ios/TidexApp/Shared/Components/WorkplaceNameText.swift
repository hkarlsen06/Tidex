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
  var badgeCornerRadius: CGFloat = CornerRadius.sm
  var badgeHorizontalPadding: CGFloat = Spacing.xs
  var badgeVerticalPadding: CGFloat = Spacing.xxxs

  var body: some View {
    if let badgeColor = resolvedBadgeColor {
      Text(name)
        .font(font)
        .foregroundColor(badgeForegroundColor(for: badgeColor))
        .lineLimit(lineLimit)
        .padding(.horizontal, badgeHorizontalPadding)
        .padding(.vertical, badgeVerticalPadding)
        .background(
          RoundedRectangle(cornerRadius: badgeCornerRadius, style: .continuous)
            .fill(Color(uiColor: badgeColor))
        )
    } else {
      Text(name)
        .font(font)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(lineLimit)
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

  private func badgeForegroundColor(for backgroundColor: UIColor) -> Color {
    let whiteContrast = contrastRatio(between: .white, and: backgroundColor)
    let blackContrast = contrastRatio(between: .black, and: backgroundColor)
    return whiteContrast >= blackContrast ? Color.white : Color.black
  }

  private func contrastRatio(between lhs: UIColor, and rhs: UIColor) -> Double {
    let lhsLuminance = relativeLuminance(for: lhs)
    let rhsLuminance = relativeLuminance(for: rhs)
    let lighter = max(lhsLuminance, rhsLuminance)
    let darker = min(lhsLuminance, rhsLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private func relativeLuminance(for color: UIColor) -> Double {
    guard let components = rgbComponents(from: color) else { return 0 }

    func linearize(_ value: CGFloat) -> Double {
      let normalized = Double(value)
      if normalized <= 0.03928 {
        return normalized / 12.92
      }
      return pow((normalized + 0.055) / 1.055, 2.4)
    }

    let red = linearize(components.red)
    let green = linearize(components.green)
    let blue = linearize(components.blue)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }

  private func rgbComponents(from color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat)?
  {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
      return (red, green, blue)
    }

    guard
      let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let converted = color.cgColor.converted(
        to: sRGBSpace,
        intent: .defaultIntent,
        options: nil
      ),
      let channels = converted.components
    else {
      return nil
    }

    if channels.count >= 3 {
      return (channels[0], channels[1], channels[2])
    }
    return nil
  }
}

/// Horizontal curated color picker for workplace colors.
struct WorkplaceColorCarousel: View {
  let selectedHex: String?
  let onSelect: (String) -> Void

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
              .frame(width: 32, height: 32)

            Circle()
              .stroke(Color.white.opacity(0.98), lineWidth: 2)
              .frame(width: 36, height: 36)
              .overlay {
                Circle()
                  .stroke(Color.black.opacity(0.25), lineWidth: 1)
                  .frame(width: 36, height: 36)
              }

            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.white)
              .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
          }
        } else {
          Circle()
            .stroke(Color.tidexBorder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: 32, height: 32)
        }
      }
      .frame(width: 40, height: 36)

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
                  .frame(width: 32, height: 32)

                if isSelected {
                  Circle()
                    .stroke(Color.white.opacity(0.98), lineWidth: 2)
                    .frame(width: 36, height: 36)
                    .overlay {
                      Circle()
                        .stroke(Color.black.opacity(0.25), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    }
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 1)
      }
    }
    .accessibilityLabel(Text(String(localized: "settings.pay.add_job.color_picker_accessibility")))
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
}
