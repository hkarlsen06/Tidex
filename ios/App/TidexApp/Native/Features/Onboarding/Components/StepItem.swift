import SwiftUI

/// Individual step item for the "How It Works" screen
struct StepItem: View {
    let icon: String
    let title: String
    let description: String
    let index: Int
    let isVisible: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(Color.tidexBlue.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
            }

            Spacer()
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.8)
                .delay(Double(index) * 0.15),
            value: isVisible
        )
    }
}

#Preview {
    VStack(spacing: 24) {
        StepItem(
            icon: "clock.badge.checkmark",
            title: "Log your shift",
            description: "Add start time, end time, done",
            index: 0,
            isVisible: true
        )

        StepItem(
            icon: "banknote",
            title: "See your earnings",
            description: "Wages calculated automatically",
            index: 1,
            isVisible: true
        )

        StepItem(
            icon: "chart.line.uptrend.xyaxis",
            title: "Track your month",
            description: "Dashboard shows your progress",
            index: 2,
            isVisible: true
        )
    }
    .padding(.horizontal, 24)
    .frame(maxHeight: .infinity)
    .background(Color.tidexBackground)
}
