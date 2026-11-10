import SwiftUI

/// Card for a user who has never added a shift. Says what adding one gives them and
/// has a full-width add button. Home shows it in place of the next-shift card.
/// When the shift from the pre-auth demo is still unsaved, the card offers that shift.
internal struct FirstShiftPrompt: View {
  internal var carriedShift: CarriedDemoShift?
  internal let onAddShift: () -> Void

  internal var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(.firstShiftPromptTitle)
          .font(.tidexTitle2)
          .foregroundStyle(Color.tidexTextPrimary)

        Group {
          if let carriedShift {
            Text(.dashboardFirstShiftCarriedMessage(Self.describe(carriedShift)))
          } else {
            Text(.firstShiftPromptMessage)
          }
        }
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)

      PrimaryButton(
        title: String(
          localized: carriedShift == nil ? .shiftsEmptyAddShift : .dashboardFirstShiftCarriedButton),
        action: onAddShift
      )
      .accessibilityIdentifier("first-shift.add-shift")
    }
  }

  /// "Wed 12 Nov 16:00–21:00", with one date per shift.
  private static func describe(_ shift: CarriedDemoShift) -> String {
    let dates = shift.dates.compactMap { Date.fromISODateString($0) }.map {
      $0.formatted(
        .dateTime.weekday(.abbreviated).day().month(.abbreviated).calendar(.gregorian)
          .locale(.appLocale))
    }
    let times = ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime, end: shift.endTime, locale: .appLocale)
    return "\(dates.formatted(.list(type: .and).locale(.appLocale))) \(times)"
  }
}

/// Full-screen version of `FirstShiftPrompt` for the Shifts list and Stats.
internal struct FirstShiftEmptyState: View {
  internal let onAddShift: () -> Void

  internal var body: some View {
    ContentUnavailableView {
      Label {
        Text(.firstShiftPromptTitle)
      } icon: {
        Image(systemName: "calendar.badge.plus")
      }
    } description: {
      Text(.firstShiftPromptMessage)
    } actions: {
      Button(action: onAddShift) {
        Label(String(localized: .shiftsEmptyAddShift), systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
      .tint(.tidexBlue)
      .accessibilityIdentifier("first-shift-empty.add-shift")
    }
  }
}

#Preview {
  VStack(spacing: Spacing.xl) {
    FirstShiftPrompt {}  // swiftlint:disable:this no_empty_block
    FirstShiftEmptyState {}  // swiftlint:disable:this no_empty_block
  }
  .padding(.horizontal, Spacing.lg)
  .background(Color.tidexBackground)
}
