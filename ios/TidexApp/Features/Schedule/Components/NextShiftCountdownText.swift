import Combine
import SwiftUI

private enum NextShiftCountdownPreviewData {
  private static let durationHours: Double = 8.0
  private static let paidHours: Double = 7.5
  private static let basePay: Double = 1_500
  private static let supplementPay: Double = 200
  private static let gross: Double = 1_700
  private static let thresholdHours: Double = 5.0
  private static let deductedHours: Double = 0.5

  static let shift: ShiftWithComputations = .init(
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
      durationHours: durationHours,
      paidHours: paidHours,
      basePay: basePay,
      supplementPay: supplementPay,
      gross: gross,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(
        method: .proportional,
        thresholdHours: thresholdHours,
        deductedHours: deductedHours,
        notes: []
      )
    ),
    taxEnabled: false,
    taxPercentage: 0
  )
}

/// Countdown text shown below the next upcoming shift card
/// Updates every second to show live countdown
internal struct NextShiftCountdownText: View {
  internal let shift: ShiftWithComputations

  @State private var countdownText: String = ""
  @State private var timer: AnyCancellable?

  internal var body: some View {
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
    countdownText =
      CountdownFormatter.formatShiftCountdown(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime
      ).text
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    NextShiftCountdownText(shift: NextShiftCountdownPreviewData.shift)
  }
  .padding()
  .background(Color.tidexBackground)
}
