import SwiftUI
import UIKit

// MARK: - Calendar View Mode Toggle

/// Reusable hours/money toggle bar for calendar views
/// Uses glass effect for selected state
struct CalendarViewModeToggle: View {
    @Binding var viewMode: CalendarViewMode
    let currency: String
    let showMoneyOption: Bool

    // Haptic feedback
    private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)

    init(
        viewMode: Binding<CalendarViewMode>,
        currency: String,
        showMoneyOption: Bool = true
    ) {
        self._viewMode = viewMode
        self.currency = currency
        self.showMoneyOption = showMoneyOption
    }

    var body: some View {
        HStack(spacing: 0) {
            // Hours button
            Button {
                guard viewMode != .hours else { return }
                toggleHaptic.impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewMode = .hours
                    viewMode.save()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("--:--")
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .medium))
                }
                .font(.system(size: 14, weight: viewMode == .hours ? .semibold : .regular))
                .foregroundColor(viewMode == .hours ? .tidexTextPrimary : .tidexTextMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
                .background(
                    Group {
                        if viewMode == .hours {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.interactive())
                        }
                    }
                )
            }
            .buttonStyle(.plain)

            // Money button (only if showing earnings)
            if showMoneyOption {
                Button {
                    guard viewMode != .money else { return }
                    toggleHaptic.impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewMode = .money
                        viewMode.save()
                    }
                } label: {
                    Text("---- \(currency)")
                        .font(.system(size: 14, weight: viewMode == .money ? .semibold : .regular))
                        .foregroundColor(viewMode == .money ? .tidexTextPrimary : .tidexTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .contentShape(Rectangle())
                        .background(
                            Group {
                                if viewMode == .money {
                                    Capsule()
                                        .fill(.clear)
                                        .glassEffect(.regular.interactive())
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.tidexSurfaceSecondary))
        .onAppear {
            toggleHaptic.prepare()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CalendarViewModeToggle(
            viewMode: .constant(.hours),
            currency: "kr"
        )

        CalendarViewModeToggle(
            viewMode: .constant(.money),
            currency: "kr"
        )

        CalendarViewModeToggle(
            viewMode: .constant(.hours),
            currency: "kr",
            showMoneyOption: false
        )
    }
    .padding()
    .background(Color.tidexBackground)
}
