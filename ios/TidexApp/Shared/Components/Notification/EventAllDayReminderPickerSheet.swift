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
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)

          HStack(spacing: Spacing.sm) {
            Picker("", selection: $daysBefore) {
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
              "",
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
          .cornerRadius(CornerRadius.lg)
          .tidexCardShadow(cornerRadius: CornerRadius.lg)
        }
        .padding(.horizontal)

        previewLabel

        Spacer()

        if isEditing, let onDelete = onDelete {
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
        .foregroundColor(.tidexBlue)

      Text(
        ReminderOffsetFormatter.localizedAllDayEventReminder(
          minutesBefore: daysBefore * 1440,
          anchorTime: anchorTime
        )
      )
      .font(.tidexLabel)
      .foregroundColor(.tidexTextPrimary)
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfaceSecondary)
    .cornerRadius(CornerRadius.sm)
    .padding(.horizontal)
  }

  @ViewBuilder
  private func deleteButton(action: @escaping () -> Void) -> some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      action()
    }) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "trash")
          .font(.tidexBody)
        Text(.commonDelete)
          .font(.tidexButton)
      }
      .foregroundColor(.tidexTextOnDanger)
      .frame(maxWidth: .infinity)
      .frame(height: Spacing.buttonHeight)
      .background(Color.tidexError)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, Spacing.md)
  }
}
