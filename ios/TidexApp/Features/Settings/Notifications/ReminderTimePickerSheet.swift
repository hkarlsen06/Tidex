import SwiftUI

enum ReminderTimePickerContext {
  case shift
  case event
}

/// Sheet for selecting a notification reminder time using hours and minutes pickers
struct ReminderTimePickerSheet: View {
  @Binding var hours: Int
  @Binding var minutes: Int
  let isEditing: Bool
  let context: ReminderTimePickerContext
  let onSave: () -> Void
  let onDelete: (() -> Void)?
  let onCancel: () -> Void
  @ScaledMetric(relativeTo: .body) private var wheelHeight: CGFloat = 180

  private var totalMinutes: Int {
    (hours * 60) + minutes
  }

  private var canSave: Bool {
    totalMinutes >= 1
  }

  init(
    hours: Binding<Int>,
    minutes: Binding<Int>,
    isEditing: Bool,
    context: ReminderTimePickerContext = .shift,
    onSave: @escaping () -> Void,
    onDelete: (() -> Void)?,
    onCancel: @escaping () -> Void
  ) {
    self._hours = hours
    self._minutes = minutes
    self.isEditing = isEditing
    self.context = context
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.md) {
          pickerSection

          // Preview label
          previewLabel
        }
        .padding(.top, Spacing.lg)
      }
      .safeAreaInset(edge: .bottom) {
        // Delete button (only when editing)
        if isEditing, let onDelete {
          deleteButton(action: onDelete)
            .padding(.bottom, Spacing.lg)
        }
      }
      .background(Color.tidexBackground)
      .navigationTitle(
        isEditing
          ? String(localized: .notificationsTimePickerEditTitle)
          : String(localized: .notificationsTimePickerAddTitle)
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbarContent }
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
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

  private var pickerSection: some View {
    VStack(spacing: Spacing.sm) {
      // Description label
      Text(descriptionText)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)

      // Dual wheel picker
      HStack(spacing: 0) {
        // Hours picker (0-48)
        Picker(String(localized: .settingsAccessibilityHours), selection: $hours) {
          ForEach(0...48, id: \.self) { hour in
            Text("\(hour) \(String(localized: .commonHoursShort))")
              .tag(hour)
          }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()

        // Minutes picker (0-59)
        Picker(String(localized: .settingsAccessibilityMinutes), selection: $minutes) {
          ForEach(0..<60, id: \.self) { minute in
            Text("\(minute) \(String(localized: .commonMinShort))")
              .tag(minute)
          }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
      }
      .frame(height: wheelHeight)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(CornerRadius.lg)
    }
    .padding(.horizontal)
  }

  @ViewBuilder
  private var previewLabel: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: canSave ? "bell.fill" : "bell.slash")
        .foregroundColor(canSave ? .tidexBlueText : .tidexTextMuted)
        .accessibilityHidden(true)

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
    switch context {
    case .shift:
      return ReminderOffsetFormatter.localizedShiftPickerPreview(hours: hours, minutes: minutes)

    case .event:
      return ReminderOffsetFormatter.localizedEventPickerPreview(hours: hours, minutes: minutes)
    }
  }

  private var descriptionText: String {
    switch context {
    case .shift:
      return String(localized: .notificationsTimePickerDescription)

    case .event:
      return String(localized: .eventsNotificationsTimedPickerDescription)
    }
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
          .accessibilityHidden(true)
        Text(.commonDelete)
          .font(.tidexButton)
      }
      .foregroundColor(.tidexTextOnDanger)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Spacing.buttonHeight)
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
    context: .shift,
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
    context: .shift,
    onSave: {},
    onDelete: {},
    onCancel: {}
  )
}
