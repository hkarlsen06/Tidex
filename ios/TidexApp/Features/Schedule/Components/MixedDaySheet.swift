import SwiftUI

struct MixedDaySheet: View {
  let dateISO: String
  let items: [DayPresentationItem]
  let excludedFromTotalIds: Set<String>
  let conflictingShiftIds: Set<String>
  let showJobIndicators: Bool
  let jobForShift: (ShiftWithComputations) -> Job?
  let onShiftTapped: (ShiftWithComputations) -> Void
  let onEventTapped: (EventRow) -> Void
  @Binding var measuredContentHeight: CGFloat

  @Environment(\.dismiss) private var dismiss

  private var sortedItems: [DayPresentationItem] {
    items.sorted { lhs, rhs in
      if lhs.isAllDayEvent != rhs.isAllDayEvent {
        return lhs.isAllDayEvent
      }
      if lhs.startSortKey != rhs.startSortKey {
        return lhs.startSortKey < rhs.startSortKey
      }
      return lhs.id < rhs.id
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.md) {
          VStack(spacing: Spacing.sm) {
            ForEach(sortedItems) { item in
              switch item {
              case .shift(let shift):
                shiftCard(shift)

              case .event(let event):
                EventRowCard(
                  event: event.event,
                  coveredDateISO: event.coveredDateISO,
                  onTap: { onEventTapped(event.event) }
                )
              }
            }
          }
        }
        .padding(Spacing.mlg)
        .measureSheetContentHeight { measuredContentHeight = $0 }
      }
      .background(Color.tidexBackground)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: .commonDone)) {
            dismiss()
          }
          .font(.tidexButton)
          .foregroundColor(.tidexBlueText)
        }
      }
    }
  }

  private func shiftCard(_ shift: ShiftWithComputations) -> some View {
    let shiftJob = jobForShift(shift)
    return ShiftRowCard(
      shift: shift,
      isToday: shift.shiftDate == todayISO(),
      hasConflict: conflictingShiftIds.contains(shift.id),
      excludedFromTotal: excludedFromTotalIds.contains(shift.id),
      showJobIndicator: showJobIndicators,
      jobName: shiftJob?.name,
      jobColorHex: shiftJob?.color,
      onTap: { onShiftTapped(shift) }
    )
  }
}
