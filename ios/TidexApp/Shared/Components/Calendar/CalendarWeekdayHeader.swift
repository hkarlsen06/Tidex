// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl
import SwiftUI

// MARK: - Calendar Weekday Header

/// Reusable weekday header row for calendar grids
/// Displays localized two-letter abbreviations (MA/TI/ON... or MO/TU/WE...)
struct CalendarWeekdayHeader: View {

  var body: some View {
    HStack(spacing: 0) {
      ForEach(weekdaySymbols.indices, id: \.self) { index in
        Text(weekdaySymbols[index])
          .font(.tidexCaption)
          .foregroundColor(.tidexTextMuted)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var weekdaySymbols: [String] {
    CalendarGridHelper.weekdaySymbols()
  }
}

// MARK: - Preview

#Preview {
  VStack {
    CalendarWeekdayHeader()
      .padding()
  }
  .background(Color.tidexBackground)
}
