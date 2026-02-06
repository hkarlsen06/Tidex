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
      VStack(spacing: 16) {
        // Picker section with description
        VStack(spacing: 12) {
          // Description label
          Text(.notificationsTimePickerDescription)
            .font(.system(size: 14))
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
          .padding(.vertical, 8)
          .background(Color.tidexSurfacePrimary)
          .cornerRadius(12)
          .tidexCardShadow(cornerRadius: 12)
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
      .padding(.top, 24)
      .padding(.bottom, 24)
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
    HStack(spacing: 8) {
      Image(systemName: canSave ? "bell.fill" : "bell.slash")
        .foregroundColor(canSave ? .tidexBlue : .tidexTextMuted)

      Text(formatPreview())
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(canSave ? .tidexTextPrimary : .tidexTextMuted)
    }
    .padding(12)
    .background(Color.tidexSurfaceSecondary)
    .cornerRadius(8)
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
      HStack(spacing: 8) {
        Image(systemName: "trash")
          .font(.system(size: 16))
        Text(.commonDelete)
          .font(.system(size: 16, weight: .semibold))
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .frame(height: Spacing.buttonHeight)
      .background(Color.tidexError)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
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
