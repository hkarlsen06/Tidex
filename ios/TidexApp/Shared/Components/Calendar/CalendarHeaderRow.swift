import SwiftUI

/// Totals shown on the trailing side of a calendar header.
/// `primary` is rendered on the month/year line. `secondary` is optional and shown below.
struct CalendarHeaderTotals: Equatable {
    let primary: Double?
    let secondary: Double?
}

/// Shared month/year header used by calendar-based screens.
/// Supports month transition animation and optional trailing totals.
struct CalendarHeaderRow: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let monthName: String
    let year: Int
    let selectionCount: Int?
    let phase: MonthTransitionPhase?
    let totals: CalendarHeaderTotals?
    let trailingAccessory: AnyView?

    @State private var lastDisplayedPrimary: Double = 0
    @State private var lastDisplayedSecondary: Double = 0

    var body: some View {
        if let totals, totals.secondary != nil {
            HStack(alignment: .center) {
                monthYearLabel

                Spacer()

                trailingContent(totals: totals, alignment: .center)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        } else {
            HStack(alignment: .firstTextBaseline) {
                monthYearLabel

                Spacer()

                if let totals {
                    trailingContent(totals: totals, alignment: .firstTextBaseline)
                } else if let trailingAccessory {
                    trailingAccessory
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var monthYearLabel: some View {
        HStack(spacing: 6) {
            Text(monthName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            if let selectionCount {
                Text("(\(selectionCount))")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
            } else {
                Text(String(year))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .modifier(HeaderTextTransitionModifier(phase: phase, layoutDirection: layoutDirection))
    }

    @ViewBuilder
    private func trailingContent(totals: CalendarHeaderTotals, alignment: VerticalAlignment) -> some View {
        HStack(alignment: alignment, spacing: 8) {
            if let trailingAccessory {
                trailingAccessory
            }
            totalsView(totals: totals)
        }
    }

    @ViewBuilder
    private func totalsView(totals: CalendarHeaderTotals) -> some View {
        if let secondary = totals.secondary {
            VStack(alignment: .trailing, spacing: 2) {
                primaryAmountText(totals.primary)
                animatedAmount(
                    secondary,
                    animateFrom: lastDisplayedSecondary > 0 ? lastDisplayedSecondary : nil
                )
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
                .onChange(of: secondary) { _, newValue in
                    lastDisplayedSecondary = newValue
                }
                .onAppear {
                    if lastDisplayedSecondary == 0 {
                        lastDisplayedSecondary = secondary
                    }
                }
            }
        } else {
            primaryAmountText(totals.primary)
        }
    }

    @ViewBuilder
    private func primaryAmountText(_ amount: Double?) -> some View {
        if let amount, amount > 0 {
            animatedAmount(
                amount,
                animateFrom: lastDisplayedPrimary > 0 ? lastDisplayedPrimary : nil
            )
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.tidexTextPrimary)
            .onChange(of: amount) { _, newValue in
                lastDisplayedPrimary = newValue
            }
            .onAppear {
                if lastDisplayedPrimary == 0 {
                    lastDisplayedPrimary = amount
                }
            }
        } else {
            Text("—")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    private func animatedAmount(_ amount: Double, animateFrom: Double?) -> some View {
        CurrencyCountUpText(
            amount: amount,
            animateOnAppear: false,
            animateFrom: animateFrom
        )
    }
}

private struct HeaderTextTransitionModifier: ViewModifier {
    let phase: MonthTransitionPhase?
    let layoutDirection: LayoutDirection

    func body(content: Content) -> some View {
        if let phase {
            content
                .id("header-\(phase.id)")
                .transition(textTransition(for: phase))
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.85),
                    value: phase.id
                )
        } else {
            content
        }
    }

    private func textTransition(for phase: MonthTransitionPhase) -> AnyTransition {
        let base: CGFloat = phase.direction == .next ? 20 : -20
        let offset = layoutDirection == .rightToLeft ? -base : base
        return .asymmetric(
            insertion: .offset(x: offset).combined(with: .opacity),
            removal: .offset(x: -offset).combined(with: .opacity)
        )
    }
}
