import SwiftUI

struct MixedDaySheet: View {
  let dateISO: String
  let items: [DayPresentationItem]
  let excludedFromTotalIds: Set<String>
  let onShiftTapped: (ShiftWithComputations) -> Void
  let onEventTapped: (EventRow) -> Void

  @Environment(\.userCurrency) private var currency
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

  private var shifts: [ShiftWithComputations] {
    sortedItems.compactMap {
      if case .shift(let shift) = $0 { return shift }
      return nil
    }
  }

  private var formattedDate: String {
    EventSheetFormatter.longDate(dateISO)
  }

  private var totalEarnings: Double {
    shifts.reduce(0) { total, shift in
      guard !excludedFromTotalIds.contains(shift.id) else { return total }
      return total + (shift.taxEnabled ? shift.netPay : shift.grossPay)
    }
  }

  private var totalHours: Double {
    shifts.reduce(0) { total, shift in
      guard !excludedFromTotalIds.contains(shift.id) else { return total }
      return total + shift.paidHours
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.md) {
          if shifts.isEmpty {
            eventOnlySummaryHeader
          } else {
            payrollSummaryHeader
          }

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
      }
      .background(Color.tidexBackground)
      .navigationTitle(formattedDate)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: .commonDone)) {
            dismiss()
          }
          .font(.tidexButton)
          .foregroundColor(.tidexBlue)
        }
      }
    }
  }

  private var payrollSummaryHeader: some View {
    HStack(spacing: Spacing.lg) {
      VStack(spacing: Spacing.xxs) {
        Text(formattedHours(totalHours))
          .font(.tidexLargeTitle)
          .foregroundColor(.tidexTextPrimary)
        Text(.shiftsDaySheetHours)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      Rectangle()
        .fill(Color.tidexBorder)
        .frame(width: 1, height: 40)

      VStack(spacing: Spacing.xxs) {
        Text(CurrencyConfig.format(totalEarnings, currency: currency))
          .font(.tidexLargeTitle)
          .foregroundColor(.tidexTextPrimary)
        Text(.shiftsDaySheetEarnings)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      countBadge
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfaceSecondary)
    )
  }

  private var eventOnlySummaryHeader: some View {
    HStack(spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(formattedDate)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)
        Text(.eventsMixedDayItems)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      countBadge
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfaceSecondary)
    )
  }

  private var countBadge: some View {
    Text("\(sortedItems.count)")
      .font(.tidexLabelStrong)
      .foregroundColor(.tidexBlue)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xxxs)
      .background(
        Capsule()
          .fill(Color.tidexBlue.opacity(0.1))
      )
  }

  private func shiftCard(_ shift: ShiftWithComputations) -> some View {
    Button {
      onShiftTapped(shift)
    } label: {
      HStack(spacing: Spacing.sm) {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(
            ShiftCardFormatter.localizedTimeRange(
              start: shift.startTime,
              end: shift.endTime,
              locale: Locale.appLocale,
              separator: " – "
            )
          )
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

          Text(formattedHours(shift.paidHours))
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: Spacing.micro) {
          Text(
            CurrencyConfig.format(
              shift.taxEnabled ? shift.netPay : shift.grossPay, currency: currency)
          )
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

          if shift.taxEnabled && shift.taxAmount > 0 {
            Text("-\(CurrencyConfig.format(shift.taxAmount, currency: currency))")
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
          }
        }

        Image(systemName: "chevron.right")
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
    .buttonStyle(.plain)
  }

  private func formattedHours(_ hours: Double) -> String {
    let formatter = FormatterCache.numberFormatter(includeDecimals: true, locale: Locale.appLocale)
    return formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.2f", hours)
  }
}
