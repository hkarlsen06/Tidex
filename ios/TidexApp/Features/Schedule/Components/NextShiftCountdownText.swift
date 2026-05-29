import Combine
import SwiftUI

/// Countdown text shown below the next upcoming shift card
/// Updates every second to show live countdown
struct NextShiftCountdownText: View {
  let shift: ShiftWithComputations

  @State private var countdownText: String = ""
  @State private var timer: AnyCancellable?

  var body: some View {
    Text(countdownText)
      .font(.tidexCaptionRegular)
      .foregroundColor(.tidexTextMuted)
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
    let (text, _, _) = CountdownFormatter.formatShiftCountdown(
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime
    )
    countdownText = text
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    NextShiftCountdownText(
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
          breakAudit: BreakAudit(
            method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
        ),
        taxEnabled: false,
        taxPercentage: 0
      )
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
