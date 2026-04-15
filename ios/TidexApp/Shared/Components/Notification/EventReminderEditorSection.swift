import SwiftUI

struct EventReminderEditorSection: View {
  @Binding var reminderTimes: [Int]
  @Binding var anchorTime: Date?
  let isAllDay: Bool
  let isEditable: Bool
  let showsPastEventHint: Bool

  @State private var showTimePickerSheet = false
  @State private var editingTimeIndex: Int?
  @State private var pickerHours = 1
  @State private var pickerMinutes = 0
  @State private var pickerDaysBefore = 0
  @State private var pickerAnchorTime = Date()

  private var canAddReminder: Bool {
    reminderTimes.count < 4
  }

  private var sortedReminderTimes: [Int] {
    reminderTimes.sorted(by: >)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      header

      if sortedReminderTimes.isEmpty && !isEditable {
        emptyState
      } else if !sortedReminderTimes.isEmpty {
        reminderRows
      }

      if isEditable && canAddReminder {
        addReminderButton
      }

      if showsPastEventHint {
        Text(String(localized: "events.notifications.past_event_hint"))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .sheet(isPresented: $showTimePickerSheet) {
      Group {
        if isAllDay {
          EventAllDayReminderPickerSheet(
            daysBefore: $pickerDaysBefore,
            anchorTime: $pickerAnchorTime,
            isEditing: editingTimeIndex != nil,
            onSave: savePickerTime,
            onDelete: editingTimeIndex != nil ? deleteCurrentReminderTime : nil,
            onCancel: { showTimePickerSheet = false }
          )
        } else {
          ReminderTimePickerSheet(
            hours: $pickerHours,
            minutes: $pickerMinutes,
            isEditing: editingTimeIndex != nil,
            context: .event,
            onSave: savePickerTime,
            onDelete: editingTimeIndex != nil ? deleteCurrentReminderTime : nil,
            onCancel: { showTimePickerSheet = false }
          )
        }
      }
      .presentationDetents([.medium])
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(String(localized: "events.notifications.section_title"))
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Text(String(localized: "events.notifications.section_description"))
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  private var emptyState: some View {
    Text(String(localized: "events.notifications.none"))
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextMuted)
  }

  private var reminderRows: some View {
    VStack(spacing: Spacing.sm) {
      ForEach(Array(sortedReminderTimes.enumerated()), id: \.offset) { index, minutes in
        Button {
          guard isEditable else { return }
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          prepareForEditingTime(minutes)
        } label: {
          HStack(spacing: Spacing.sm) {
            Image(systemName: "bell.fill")
              .font(.tidexBody)
              .foregroundColor(.tidexBlue)
              .frame(width: 24)

            Text(reminderLabel(for: minutes))
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)

            Spacer()

            if isEditable {
              Image(systemName: "pencil")
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextMuted)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityIdentifier("event-reminder-row-\(index)")
      }
    }
  }

  private var addReminderButton: some View {
    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      prepareForAddingTime()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "plus.circle.fill")
          .font(.tidexBody)
          .foregroundColor(.tidexBlue)

        Text(.notificationsRemindersAddTime)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
      }
    }
    .buttonStyle(.plain)
  }

  private func defaultAnchorTime() -> Date {
    let calendar = Calendar.current
    let baseDate = Date()
    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate
  }

  private func prepareForAddingTime() {
    editingTimeIndex = nil
    if isAllDay {
      pickerDaysBefore = 0
      pickerAnchorTime = anchorTime ?? defaultAnchorTime()
    } else {
      pickerHours = 1
      pickerMinutes = 0
    }
    showTimePickerSheet = true
  }

  private func prepareForEditingTime(_ minutes: Int) {
    editingTimeIndex = sortedReminderTimes.firstIndex(of: minutes)
    if isAllDay {
      pickerDaysBefore = max(0, min(2, minutes / 1440))
      pickerAnchorTime = anchorTime ?? defaultAnchorTime()
    } else {
      pickerHours = minutes / 60
      pickerMinutes = minutes % 60
    }
    showTimePickerSheet = true
  }

  private func savePickerTime() {
    let totalMinutes: Int
    if isAllDay {
      totalMinutes = pickerDaysBefore * 1440
    } else {
      totalMinutes = (pickerHours * 60) + pickerMinutes
      guard totalMinutes >= 1 else { return }
    }

    var updated = sortedReminderTimes
    if let editingTimeIndex {
      updated.remove(at: editingTimeIndex)
    }

    guard !updated.contains(totalMinutes) else {
      showTimePickerSheet = false
      return
    }

    updated.append(totalMinutes)
    reminderTimes = LocalEvent.normalizedReminderMinutes(updated)

    if isAllDay {
      anchorTime = pickerAnchorTime
    }

    showTimePickerSheet = false
  }

  private func reminderLabel(for minutes: Int) -> String {
    if isAllDay {
      return ReminderOffsetFormatter.localizedAllDayEventReminder(
        minutesBefore: minutes,
        anchorTime: anchorTime
      )
    }
    return ReminderOffsetFormatter.localizedString(for: minutes)
  }

  private func deleteCurrentReminderTime() {
    guard let editingTimeIndex else { return }

    var updated = sortedReminderTimes
    updated.remove(at: editingTimeIndex)
    reminderTimes = LocalEvent.normalizedReminderMinutes(updated)

    if updated.isEmpty {
      anchorTime = nil
    }

    showTimePickerSheet = false
  }
}
