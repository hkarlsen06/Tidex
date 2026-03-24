import SwiftUI

enum ShiftCardMetrics {
  static let verticalPadding: CGFloat = Spacing.md
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
  private let leadingTop: LeadingTop
  private let leadingBottom: LeadingBottom
  private let trailingTop: TrailingTop
  private let trailingBottom: TrailingBottom

  init(
    rowSpacing: CGFloat = 4,
    centerTrailing: Bool = false,
    @ViewBuilder leadingTop: () -> LeadingTop,
    @ViewBuilder leadingBottom: () -> LeadingBottom,
    @ViewBuilder trailingTop: () -> TrailingTop,
    @ViewBuilder trailingBottom: () -> TrailingBottom
  ) {
    self.rowSpacing = rowSpacing
    self.centerTrailing = centerTrailing
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

        Spacer(minLength: Spacing.xs)

        VStack(alignment: .trailing, spacing: rowSpacing) {
          trailingTop
          trailingBottom
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
      }
    } else {
      // Row-based: each row aligns left/right by baseline
      VStack(spacing: rowSpacing) {
        HStack(alignment: .lastTextBaseline) {
          leadingTop
            .lineLimit(1)
          Spacer(minLength: Spacing.xs)
          trailingTop
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        HStack(alignment: .firstTextBaseline) {
          leadingBottom
            .lineLimit(1)
          Spacer(minLength: Spacing.xs)
          trailingBottom
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
      }
    }
  }
}
