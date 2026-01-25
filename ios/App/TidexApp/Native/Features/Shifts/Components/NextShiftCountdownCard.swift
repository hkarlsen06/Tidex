import SwiftUI
import Combine

/// A card showing countdown to the next upcoming shift
/// Updates every second when the countdown is active
struct NextShiftCountdownCard: View {
    let shift: ShiftWithComputations

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    @State private var countdownText: String = ""
    @State private var isActive: Bool = false
    @State private var timer: AnyCancellable?

    private var isNorwegian: Bool {
        localization.currentLocale == .norwegian
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {
            // Left: countdown badge
            VStack(spacing: 4) {
                // Status indicator
                Circle()
                    .fill(isActive ? Color.green : Color.tidexBlue)
                    .frame(width: 8, height: 8)

                // Countdown text
                Text(countdownText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? .green : .tidexBlue)
            }
            .frame(width: 80)

            // Divider
            Rectangle()
                .fill(Color.tidexBorder)
                .frame(width: 1)
                .padding(.vertical, 8)

            // Right: shift info
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(isActive
                     ? (isNorwegian ? "Pågående vakt" : "Current shift")
                     : (isNorwegian ? "Neste vakt" : "Next shift")
                )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                // Date and time
                HStack(spacing: 8) {
                    Text(formattedDate)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                    Text("·")
                        .foregroundColor(.tidexTextMuted)
                    Text(formattedTimeRange)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                }
            }

            Spacer()

            // Earnings
            Text(formatCurrency(shift.taxEnabled ? shift.netPay : shift.grossPay))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tidexSurfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isActive ? Color.green.opacity(0.3) : Color.tidexBlue.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            updateCountdown()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updateCountdown()
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func updateCountdown() {
        let (text, active, _) = CountdownFormatter.formatShiftCountdown(
            shiftDate: shift.shiftDate,
            startTime: shift.startTime,
            endTime: shift.endTime,
            isNorwegian: isNorwegian
        )
        countdownText = text
        isActive = active
    }

    // MARK: - Formatting

    private var formattedDate: String {
        guard let date = Date.fromISODateString(shift.shiftDate) else {
            return shift.shiftDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: date).capitalized
    }

    private var formattedTimeRange: String {
        "\(formatTime(shift.startTime))–\(formatTime(shift.endTime))"
    }

    private func formatTime(_ time: String) -> String {
        String(time.prefix(5))
    }

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        NextShiftCountdownCard(
            shift: ShiftWithComputations(
                shift: ShiftRow(
                    id: "preview-1",
                    user_id: "user-1",
                    shift_date: todayISO(),
                    start_time: "14:00",
                    end_time: "22:00",
                    custom_supplements: nil
                ),
                computed: ShiftComputed(
                    id: "preview-1",
                    durationHours: 8.0,
                    paidHours: 7.5,
                    basePay: 1500,
                    supplementPay: 200,
                    gross: 1700,
                    wagePeriods: [],
                    originalWagePeriods: [],
                    breakAudit: BreakAudit(method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
                ),
                taxEnabled: false,
                taxPercentage: 0
            )
        )
    }
    .padding()
    .background(Color.tidexBackground)
}
