import SwiftUI

/// Time period for empty state messaging
enum MonthPeriod {
    case past
    case current
    case future
}

/// Empty state view when there are no shifts for the displayed month
struct ShiftsEmptyState: View {
    /// Whether this is showing for the current month (vs a past/future month)
    let isCurrentMonth: Bool
    /// The month period for more specific messaging
    let monthPeriod: MonthPeriod
    /// Display month name for context
    let monthName: String?
    /// Callback when user taps "Add Shift" button
    let onAddShift: () -> Void

    @Environment(\.localization) private var localization

    private var isNorwegian: Bool {
        localization.currentLocale == .norwegian
    }

    // Convenience init for backward compatibility
    init(isCurrentMonth: Bool, onAddShift: @escaping () -> Void) {
        self.isCurrentMonth = isCurrentMonth
        self.monthPeriod = isCurrentMonth ? .current : .past
        self.monthName = nil
        self.onAddShift = onAddShift
    }

    // Full init with period
    init(isCurrentMonth: Bool, monthPeriod: MonthPeriod, monthName: String?, onAddShift: @escaping () -> Void) {
        self.isCurrentMonth = isCurrentMonth
        self.monthPeriod = monthPeriod
        self.monthName = monthName
        self.onAddShift = onAddShift
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon - changes based on period
            Image(systemName: iconName)
                .font(.system(size: 56, weight: .light))
                .foregroundColor(iconColor.opacity(0.6))

            // Title
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

            // Subtitle - context-aware message
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Action buttons based on period
            actionButtons
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch monthPeriod {
        case .past:
            return "clock.arrow.circlepath"
        case .current:
            return "calendar.badge.plus"
        case .future:
            return "calendar.badge.clock"
        }
    }

    private var iconColor: Color {
        switch monthPeriod {
        case .past:
            return .tidexTextMuted
        case .current:
            return .tidexBlue
        case .future:
            return .tidexBlue
        }
    }

    private var title: String {
        switch monthPeriod {
        case .past:
            return isNorwegian ? "Ingen vakter" : "No shifts"
        case .current:
            return isNorwegian ? "Ingen vakter denne måneden" : "No shifts this month"
        case .future:
            if let name = monthName {
                return isNorwegian ? "Ingen vakter i \(name)" : "No shifts in \(name)"
            }
            return isNorwegian ? "Ingen vakter planlagt" : "No shifts planned"
        }
    }

    private var subtitle: String {
        switch monthPeriod {
        case .past:
            if let name = monthName {
                return isNorwegian
                    ? "Du hadde ingen registrerte vakter i \(name.lowercased())."
                    : "You had no recorded shifts in \(name.lowercased())."
            }
            return isNorwegian
                ? "Ingen vakter ble registrert denne måneden."
                : "No shifts were recorded for this month."
        case .current:
            return isNorwegian
                ? "Legg til din første vakt for å begynne å spore inntektene dine."
                : "Add your first shift to start tracking your earnings."
        case .future:
            return isNorwegian
                ? "Du kan planlegge vakter på forhånd, eller sette opp gjentakende vakter."
                : "You can plan shifts ahead, or set up recurring shifts."
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch monthPeriod {
        case .past:
            // No action for past months
            EmptyView()
        case .current, .future:
            Button(action: onAddShift) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isNorwegian ? "Legg til vakt" : "Add shift")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.tidexBlue)
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Preview

#Preview("Current Month") {
    ShiftsEmptyState(
        isCurrentMonth: true,
        monthPeriod: .current,
        monthName: "January"
    ) {
        print("Add shift tapped")
    }
    .background(Color.tidexBackground)
}

#Preview("Past Month") {
    ShiftsEmptyState(
        isCurrentMonth: false,
        monthPeriod: .past,
        monthName: "December"
    ) {
        print("Add shift tapped")
    }
    .background(Color.tidexBackground)
}

#Preview("Future Month") {
    ShiftsEmptyState(
        isCurrentMonth: false,
        monthPeriod: .future,
        monthName: "February"
    ) {
        print("Add shift tapped")
    }
    .background(Color.tidexBackground)
}
