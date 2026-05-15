import SwiftUI

enum ShiftCardMetrics {
  static let verticalPadding: CGFloat = Spacing.md
  static let regularCardMinHeight: CGFloat = 89
}

/// Shared two-row card layout used by feature-specific cards.
/// Each row is its own HStack so left/right items align per-row regardless of font size.
///
/// When `centerTrailing` is true, the trailing content floats vertically centered
/// against the full card height (use when there's no breakdown row).
struct ShiftCardContentLayout<
  LeadingTop: View, LeadingBottom: View, TrailingTop: View, TrailingBottom: View
>: View {
  private let rowSpacing: CGFloat
  private let centerTrailing: Bool
  private let leadingLayoutPriority: Double
  private let trailingLayoutPriority: Double
  private let trailingFixedHorizontal: Bool
  private let topRowAlignment: VerticalAlignment
  private let leadingTop: LeadingTop
  private let leadingBottom: LeadingBottom
  private let trailingTop: TrailingTop
  private let trailingBottom: TrailingBottom

  init(
    rowSpacing: CGFloat = 4,
    centerTrailing: Bool = false,
    leadingLayoutPriority: Double = 0,
    trailingLayoutPriority: Double = 1,
    trailingFixedHorizontal: Bool = true,
    topRowAlignment: VerticalAlignment = .lastTextBaseline,
    @ViewBuilder leadingTop: () -> LeadingTop,
    @ViewBuilder leadingBottom: () -> LeadingBottom,
    @ViewBuilder trailingTop: () -> TrailingTop,
    @ViewBuilder trailingBottom: () -> TrailingBottom
  ) {
    self.rowSpacing = rowSpacing
    self.centerTrailing = centerTrailing
    self.leadingLayoutPriority = leadingLayoutPriority
    self.trailingLayoutPriority = trailingLayoutPriority
    self.trailingFixedHorizontal = trailingFixedHorizontal
    self.topRowAlignment = topRowAlignment
    self.leadingTop = leadingTop()
    self.leadingBottom = leadingBottom()
    self.trailingTop = trailingTop()
    self.trailingBottom = trailingBottom()
  }

  var body: some View {
    if centerTrailing {
      // Column-based: trailing content floats centered vertically
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: rowSpacing) {
          leadingTop
          leadingBottom
        }
        .lineLimit(1)
        .layoutPriority(leadingLayoutPriority)

        Spacer(minLength: Spacing.xs)

        VStack(alignment: .trailing, spacing: rowSpacing) {
          trailingTop
          trailingBottom
        }
        .fixedSize(horizontal: trailingFixedHorizontal, vertical: false)
        .layoutPriority(trailingLayoutPriority)
      }
    } else {
      // Row-based: each row aligns left/right by baseline
      VStack(spacing: rowSpacing) {
        HStack(alignment: topRowAlignment) {
          leadingTop
            .lineLimit(1)
            .layoutPriority(leadingLayoutPriority)
          Spacer(minLength: Spacing.xs)
          trailingTop
            .fixedSize(horizontal: trailingFixedHorizontal, vertical: false)
            .layoutPriority(trailingLayoutPriority)
        }
        HStack(alignment: .firstTextBaseline) {
          leadingBottom
            .lineLimit(1)
            .layoutPriority(leadingLayoutPriority)
          Spacer(minLength: Spacing.xs)
          trailingBottom
            .fixedSize(horizontal: trailingFixedHorizontal, vertical: false)
            .layoutPriority(trailingLayoutPriority)
        }
      }
    }
  }
}
