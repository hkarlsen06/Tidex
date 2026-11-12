// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers number_separator shorthand_optional_binding
import SwiftUI

struct EventAllDayReminderPickerSheet: View {
  @Binding var daysBefore: Int
  @Binding var anchorTime: Date
  let isEditing: Bool
  let onSave: () -> Void
  let onDelete: (() -> Void)?
  let onCancel: () -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: Spacing.md) {
        VStack(spacing: Spacing.sm) {
          Text(.eventsNotificationsAllDayPickerDescription)
            .font(.tidexSubheadline)
            .foregroundStyle(Color.tidexTextSecondary)
            .multilineTextAlignment(.center)

          HStack(spacing: Spacing.sm) {
            Picker(String(localized: .commonAccessibilityReminderDay), selection: $daysBefore) {
              Text(.eventsNotificationsSameDay)
                .tag(0)
              Text(.eventsNotificationsOneDayBefore)
                .tag(1)
              Text(.eventsNotificationsTwoDaysBefore)
                .tag(2)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            DatePicker(
              String(localized: .commonAccessibilityReminderTime),
              selection: $anchorTime,
              displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
          }
          .frame(height: 180)
          .padding(.vertical, Spacing.xs)
          .background(Color.tidexSurfacePrimary)
          .clipShape(.rect(cornerRadius: CornerRadius.lg))
        }
        .padding(.horizontal)

        previewLabel

        Spacer()

        if isEditing, let onDelete {
          deleteButton(action: onDelete)
        }
      }
      .padding(.top, Spacing.lg)
      .padding(.bottom, Spacing.lg)
      .background(Color.tidexBackground)
      .navigationTitle(
        isEditing
          ? String(localized: .notificationsTimePickerEditTitle)
          : String(localized: .notificationsTimePickerAddTitle)
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            onCancel()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonSave)) {
            onSave()
          }
          .fontWeight(.semibold)
        }
      }
    }
  }

  private var previewLabel: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "bell.fill")
        .foregroundStyle(Color.tidexBlueText)
        .accessibilityHidden(true)

      Text(
        ReminderOffsetFormatter.localizedAllDayEventReminder(
          minutesBefore: daysBefore * 1_440,
          anchorTime: anchorTime
        )
      )
      .font(.tidexLabel)
      .foregroundStyle(Color.tidexTextPrimary)
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(.rect(cornerRadius: CornerRadius.sm))
    .padding(.horizontal)
  }

  @ViewBuilder
  private func deleteButton(action: @escaping () -> Void) -> some View {
    Button(action: {
      Haptics.play(.medium)
      action()
    }) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "trash")
          .font(.tidexBody)
        Text(.commonDelete)
          .font(.tidexButton)
      }
      .foregroundStyle(Color.tidexTextOnDanger)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Spacing.buttonHeight)
      .background(Color.tidexError)
      .clipShape(Capsule())
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, Spacing.md)
  }
}
