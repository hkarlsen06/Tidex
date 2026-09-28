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

  internal var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      Text(countdownText(at: context.date))
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private func countdownText(at date: Date) -> String {
    CountdownFormatter.formatShiftCountdown(
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      now: date
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
