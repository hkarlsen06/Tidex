import SwiftUI

/// Sheet for selecting a notification reminder time using hours and minutes pickers
struct ReminderTimePickerSheet: View {
  @Binding var hours: Int
  @Binding var minutes: Int
  let isEditing: Bool
  let onSave: () -> Void
  let onDelete: (() -> Void)?
  let onCancel: () -> Void

  private var totalMinutes: Int {
    (hours * 60) + minutes
  }

  private var canSave: Bool {
    totalMinutes >= 1
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: Spacing.md) {
        // Picker section with description
        VStack(spacing: Spacing.sm) {
          // Description label
          Text(.notificationsTimePickerDescription)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)

          // Dual wheel picker
          HStack(spacing: 0) {
            // Hours picker (0-48)
            Picker("", selection: $hours) {
              ForEach(0...48, id: \.self) { h in
                Text("\(h) \(String(localized: .commonHoursShort))")
                  .tag(h)
              }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            // Minutes picker (0-59)
            Picker("", selection: $minutes) {
              ForEach(0..<60, id: \.self) { m in
                Text("\(m) min")
                  .tag(m)
              }
            }
            .pickerStyle(.wheel)
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

        // Preview label
        previewLabel

        Spacer()

        // Delete button (only when editing)
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
          .disabled(!canSave)
          .fontWeight(.semibold)
        }
      }
    }
  }

  @ViewBuilder
  private var previewLabel: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: canSave ? "bell.fill" : "bell.slash")
        .foregroundColor(canSave ? .tidexBlue : .tidexTextMuted)

      Text(formatPreview())
        .font(.tidexLabel)
        .foregroundColor(canSave ? .tidexTextPrimary : .tidexTextMuted)
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfaceSecondary)
    .cornerRadius(CornerRadius.sm)
    .padding(.horizontal)
  }

  private func formatPreview() -> String {
    guard totalMinutes >= 1 else {
      return String(localized: .notificationsTimePickerSelectTime)
    }

    let h = hours
    let m = minutes

    if h == 0 {
      // Minutes only
      return String(localized: .notificationReminderMinutesBeforeShift(Int(m)))
    } else if m == 0 {
      // Hours only
      if h == 24 {
        return String(localized: .notificationReminderOneDayBeforeShift)
      } else if h == 48 {
        return String(localized: .notificationReminderTwoDaysBeforeShift)
      }
      return String(localized: .notificationReminderHoursBeforeShift(Int(h)))
    } else {
      // Mixed hours and minutes
      return
        "\(h) \(String(localized: .commonHoursShort)) \(m) min \(String(localized: .commonBeforeShift))"
    }
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
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .frame(height: Spacing.buttonHeight)
      .background(Color.tidexError)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, Spacing.md)
  }
}

// MARK: - Preview

#Preview("Add Mode") {
  ReminderTimePickerSheet(
    hours: .constant(1),
    minutes: .constant(0),
    isEditing: false,
    onSave: {},
    onDelete: nil,
    onCancel: {}
  )
}

#Preview("Edit Mode") {
  ReminderTimePickerSheet(
    hours: .constant(5),
    minutes: .constant(30),
    isEditing: true,
    onSave: {},
    onDelete: {},
    onCancel: {}
  )
}
