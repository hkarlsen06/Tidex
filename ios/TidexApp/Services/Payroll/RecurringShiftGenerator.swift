/// Adapts recurring app models to the generator used by payroll and sharing.
struct RecurringShiftGenerator {
  static func isInPhase(dateISO: String, anchorISO: String, interval: Int) -> Bool {
    SharingComputeCore.isInPhase(dateISO: dateISO, anchorISO: anchorISO, interval: interval)
  }

  static func generateVirtualShiftsForMonth(
    year: Int,
    month: Int,
    recurring: RecurringShiftRow
  ) -> [RecurringVirtualShift] {
    SharingComputeCore.generateVirtualShiftsForMonth(
      year: year, month: month, recurring: PayrollEngine.sharingRecurring(recurring)
    ).map { RecurringVirtualShift(date: $0.date, weekday: $0.weekday) }
  }
}
