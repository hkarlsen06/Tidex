import SwiftUI

/// Shared two-row shift card layout used by feature-specific cards.
/// Keeps leading content on the left and amount/breakdown content on the right.
struct ShiftCardContentLayout<LeadingTop: View, LeadingBottom: View, TrailingTop: View, TrailingBottom: View>: View {
    private let columnSpacing: CGFloat?
    private let leadingSpacing: CGFloat
    private let trailingSpacing: CGFloat
    private let leadingTop: LeadingTop
    private let leadingBottom: LeadingBottom
    private let trailingTop: TrailingTop
    private let trailingBottom: TrailingBottom

    init(
        columnSpacing: CGFloat? = nil,
        leadingSpacing: CGFloat = 4,
        trailingSpacing: CGFloat = 4,
        @ViewBuilder leadingTop: () -> LeadingTop,
        @ViewBuilder leadingBottom: () -> LeadingBottom,
        @ViewBuilder trailingTop: () -> TrailingTop,
        @ViewBuilder trailingBottom: () -> TrailingBottom
    ) {
        self.columnSpacing = columnSpacing
        self.leadingSpacing = leadingSpacing
        self.trailingSpacing = trailingSpacing
        self.leadingTop = leadingTop()
        self.leadingBottom = leadingBottom()
        self.trailingTop = trailingTop()
        self.trailingBottom = trailingBottom()
    }

    var body: some View {
        HStack(alignment: .center, spacing: columnSpacing) {
            VStack(alignment: .leading, spacing: leadingSpacing) {
                leadingTop
                leadingBottom
            }

            Spacer()

            VStack(alignment: .trailing, spacing: trailingSpacing) {
                trailingTop
                trailingBottom
            }
        }
    }
}
