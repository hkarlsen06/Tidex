import SwiftUI

/// Small stat card for displaying a single metric (hours, shifts, etc.)
/// Used in a 2-column grid layout
struct SmallStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with title and icon
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.tidexTextMuted)
            }

            // Value
            Text(value)
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.tidexBorderSubtle, lineWidth: 1)
        )
    }
}

/// Hours stat card with decimal formatting
struct HoursStatCard: View {
    let hours: Double

    @Environment(\.localization) private var localization

    var body: some View {
        SmallStatCard(
            title: localization.string("stats.hours"),
            value: formatHours(hours),
            icon: "clock"
        )
    }

    private func formatHours(_ hours: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale(identifier: "nb_NO")
        return formatter.string(from: NSNumber(value: hours)) ?? "\(Int(hours))"
    }
}

/// Shifts count stat card
struct ShiftsStatCard: View {
    let count: Int

    @Environment(\.localization) private var localization

    var body: some View {
        SmallStatCard(
            title: localization.string("stats.shifts"),
            value: "\(count)",
            icon: "calendar"
        )
    }
}

#Preview {
    HStack(spacing: 12) {
        HoursStatCard(hours: 60.3)
        ShiftsStatCard(count: 9)
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
