import SwiftUI

/// Popover content for mixed-currency totals.
/// The view wraps long labels and allows vertical scrolling when needed.
struct MixedCurrencyBreakdownPopover: View {
  let entries: [JobCurrencyAggregateEntry]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        ForEach(entries.indices, id: \.self) { index in
          let entry = entries[index]

          HStack(alignment: .top, spacing: Spacing.sm) {
            Text(entry.jobName)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)
              .lineLimit(nil)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.sm)

            Text(CurrencyConfig.format(entry.displayAmount, currency: entry.currency))
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextSecondary)
              .lineLimit(nil)
              .multilineTextAlignment(.trailing)
              .fixedSize(horizontal: false, vertical: true)
          }

          if index < entries.count - 1 {
            Divider()
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
    }
    .frame(minWidth: 220, idealWidth: 280, maxWidth: 320, maxHeight: 260)
    .background(Color.tidexSurfacePrimary)
  }
}

#Preview {
  MixedCurrencyBreakdownPopover(
    entries: [
      JobCurrencyAggregateEntry(
        key: "1|kr",
        jobId: "1",
        jobName: "Very long workplace name that should wrap to multiple lines in the tooltip",
        currency: "kr",
        grossAmount: 3200,
        netAmount: 2990,
        displayAmount: 2990,
        shiftCount: 3,
        completedShiftCount: 2,
        plannedShiftCount: 1,
        hasTaxEnabled: true
      ),
      JobCurrencyAggregateEntry(
        key: "2|$",
        jobId: "2",
        jobName: "Cafe Evening Shift",
        currency: "$",
        grossAmount: 980,
        netAmount: 980,
        displayAmount: 980,
        shiftCount: 2,
        completedShiftCount: 2,
        plannedShiftCount: 0,
        hasTaxEnabled: false
      ),
    ]
  )
  .padding()
  .background(Color.tidexBackground)
}
