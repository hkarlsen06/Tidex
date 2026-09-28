import SwiftUI

/// Card for a user who has never added a shift. Says what adding one gives them and
/// has a full-width add button. Home shows it in place of the next-shift card.
internal struct FirstShiftPrompt: View {
  internal let onAddShift: () -> Void

  internal var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(.firstShiftPromptTitle)
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)

        Text(.firstShiftPromptMessage)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)

      PrimaryButton(title: String(localized: .shiftsEmptyAddShift), action: onAddShift)
        .accessibilityIdentifier("first-shift.add-shift")
    }
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
