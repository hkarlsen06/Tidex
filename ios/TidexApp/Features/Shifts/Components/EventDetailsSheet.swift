import SwiftUI

struct EventEditResult {
  let eventId: String
  let startDate: String
  let endDate: String
  let isAllDay: Bool
  let startTime: String?
  let endTime: String?
  let note: String
}

struct EventDetailsSheet: View {
  let event: EventRow
  let onDelete: (() -> Void)?
  let onUpdate: ((EventEditResult) -> Void)?
  var startInEditMode: Bool = false

  @Environment(\.dismiss) private var dismiss

  @State private var isEditing = false
  @State private var editedNote = ""
  @State private var isAllDay = false
  @State private var eventDate = Date()
  @State private var eventStartDate = Date()
  @State private var eventEndDate = Date()
  @State private var editedStartTime: Date?
  @State private var editedEndTime: Date?
  @State private var focusedTimeField: TimeInputField?
  @State private var errorMessage: String?

  private var trimmedNote: String {
    editedNote.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var normalizedStartTimeString: String? {
    editedStartTime?.toHourMinuteString()
  }

  private var normalizedEndTimeString: String? {
    guard let editedEndTime else { return nil }

    let formatted = editedEndTime.toHourMinuteString()
    if formatted == "00:00", let normalizedStartTimeString, normalizedStartTimeString != "00:00" {
      return "24:00"
    }
    return formatted
  }

  private var isTimeRangeValid: Bool {
    guard let normalizedStartTimeString, let normalizedEndTimeString else { return false }
    return normalizedEndTimeString > normalizedStartTimeString
  }

  private var canSave: Bool {
    guard !trimmedNote.isEmpty else { return false }
    if isAllDay {
      return eventEndDate >= eventStartDate
    }
    return isTimeRangeValid
  }

  private var formattedDate: String {
    EventSheetFormatter.longDate(event.start_date)
  }

  private var formattedStartDate: String {
    EventSheetFormatter.longDate(event.start_date)
  }

  private var formattedEndDate: String {
    EventSheetFormatter.longDate(event.end_date)
  }

  private var formattedTimeRange: String {
    guard let start = event.start_time, let end = event.end_time else {
      return String(localized: .addShiftEventAllDay)
    }

    return ShiftCardFormatter.localizedTimeRange(
      start: start,
      end: end,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.lg) {
          if isEditing {
            editorContent
          } else {
            detailsContent
          }

          if let errorMessage {
            errorBanner(message: errorMessage)
          }

          actionButtons
        }
        .padding(Spacing.mlg)
      }
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .addShiftModeEvents))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if isEditing {
            Button(String(localized: .commonCancel)) {
              resetDraft()
              withAnimation(.easeInOut(duration: 0.2)) {
                isEditing = false
              }
            }
            .foregroundColor(.tidexTextSecondary)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          if isEditing {
            Button(String(localized: .commonSave)) {
              saveChanges()
            }
            .font(.tidexButton)
            .foregroundColor(canSave ? .tidexBlue : .tidexTextMuted)
            .disabled(!canSave)
          } else {
            Button(String(localized: .commonDone)) {
              dismiss()
            }
            .font(.tidexButton)
            .foregroundColor(.tidexBlue)
          }
        }
      }
      .onAppear {
        resetDraft()
        isEditing = startInEditMode
      }
      .onChange(of: isAllDay) { _, newValue in
        if newValue {
          eventStartDate = eventDate
          if eventEndDate < eventStartDate {
            eventEndDate = eventStartDate
          }
          editedStartTime = nil
          editedEndTime = nil
        } else {
          eventDate = eventStartDate
          eventEndDate = eventStartDate
        }
      }
      .onChange(of: eventStartDate) { _, newValue in
        if isAllDay, eventEndDate < newValue {
          eventEndDate = newValue
        }
        if !isAllDay {
          eventDate = newValue
          eventEndDate = newValue
        }
      }
      .onChange(of: eventDate) { _, newValue in
        if !isAllDay {
          eventStartDate = newValue
          eventEndDate = newValue
        }
      }
    }
  }

  private var detailsContent: some View {
    VStack(spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        scheduleBadge

        Text(event.note)
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(Spacing.lg)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )

      VStack(spacing: Spacing.sm) {
        detailRow(title: String(localized: .addShiftEventNoteTitle), value: event.note)

        if event.is_all_day {
          detailRow(title: String(localized: .addShiftEventStartDate), value: formattedStartDate)
          detailRow(title: String(localized: .addShiftEventEndDate), value: formattedEndDate)
        } else {
          detailRow(title: String(localized: .addShiftEventDate), value: formattedDate)
          detailRow(title: String(localized: .commonStart), value: event.start_time ?? "--:--")
          detailRow(title: String(localized: .commonEnd), value: event.end_time ?? "--:--")
        }
      }
      .padding(Spacing.lg)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  private var editorContent: some View {
    VStack(spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(.addShiftEventNoteTitle)
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)

        TextEditor(text: $editedNote)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 120)
          .padding(Spacing.sm)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
              .fill(Color.tidexBackground)
          )
      }
      .padding(Spacing.lg)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )

      Toggle(isOn: $isAllDay) {
        Text(.addShiftEventAllDay)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
      }
      .tint(.tidexBlue)
      .padding(Spacing.lg)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )

      if isAllDay {
        VStack(spacing: Spacing.sm) {
          dateEditor(title: String(localized: .addShiftEventStartDate), selection: $eventStartDate)
          dateEditor(title: String(localized: .addShiftEventEndDate), selection: $eventEndDate)
        }
      } else {
        VStack(spacing: Spacing.sm) {
          dateEditor(title: String(localized: .addShiftEventDate), selection: $eventDate)

          TimeRangePicker(
            startTime: $editedStartTime,
            endTime: $editedEndTime,
            scrollProxy: nil,
            scrollId: "event-details-time-range",
            focusedFieldBinding: $focusedTimeField,
            leadingChipAccessory: nil
          )
        }
      }
    }
  }

  private var actionButtons: some View {
    VStack(spacing: Spacing.sm) {
      if !isEditing {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
          }
        } label: {
          Text(.shiftsActionsEdit)
            .font(.tidexButton)
            .foregroundColor(.tidexBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
              RoundedRectangle(cornerRadius: CornerRadius.xxl)
                .fill(Color.tidexSurfacePrimary)
            )
        }
        .buttonStyle(.plain)
      }

      Button(role: .destructive) {
        onDelete?()
      } label: {
        Text(.eventsDeleteButton)
          .font(.tidexButton)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.md)
      }
      .buttonStyle(.plain)
      .foregroundColor(.red)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  private var scheduleBadge: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: event.is_all_day ? "calendar" : "clock")
        .font(.tidexFootnote)
      Text(event.is_all_day ? String(localized: .addShiftEventAllDay) : formattedTimeRange)
        .font(.tidexSubheadline)
    }
    .foregroundColor(.tidexBlue)
  }

  private func detailRow(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(title)
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexTextMuted)

      Text(value)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func dateEditor(title: String, selection: Binding<Date>) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(title)
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexTextMuted)

      DatePicker(
        "",
        selection: selection,
        displayedComponents: .date
      )
      .datePickerStyle(.compact)
      .labelsHidden()
      .tint(.tidexBlue)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(Spacing.lg)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }

  private func errorBanner(message: String) -> some View {
    Text(message)
      .font(.tidexSubheadline)
      .foregroundColor(.red)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.red.opacity(0.08))
      )
  }

  private func resetDraft() {
    editedNote = event.note
    isAllDay = event.is_all_day
    eventDate = Date.fromISODateString(event.start_date) ?? Date()
    eventStartDate = Date.fromISODateString(event.start_date) ?? eventDate
    eventEndDate = Date.fromISODateString(event.end_date) ?? eventStartDate
    editedStartTime = EventSheetFormatter.date(from: event.start_time)
    editedEndTime = EventSheetFormatter.date(from: event.end_time)
    errorMessage = nil
  }

  private func saveChanges() {
    guard canSave else {
      errorMessage = String(localized: .eventsValidationMessage)
      return
    }

    let result = EventEditResult(
      eventId: event.id,
      startDate: (isAllDay ? eventStartDate : eventDate).toISODateString(),
      endDate: (isAllDay ? eventEndDate : eventDate).toISODateString(),
      isAllDay: isAllDay,
      startTime: isAllDay ? nil : normalizedStartTimeString,
      endTime: isAllDay ? nil : normalizedEndTimeString,
      note: trimmedNote
    )

    onUpdate?(result)
  }
}

enum EventSheetFormatter {
  static func date(from hhmm: String?) -> Date? {
    guard let hhmm else { return nil }
    let parts = hhmm.split(separator: ":")
    guard
      parts.count == 2,
      let hour = Int(parts[0]),
      let minute = Int(parts[1])
    else {
      return nil
    }

    let is24 = hour == 24 && minute == 0
    var calendar = Calendar.current
    calendar.timeZone = Date.localTimeZone
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = is24 ? 0 : hour
    components.minute = minute
    return calendar.date(from: components)
  }

  static func longDate(_ isoDate: String) -> String {
    guard let date = Date.fromISODateString(isoDate) else { return isoDate }
    let formatter = DateFormatter()
    formatter.locale = Locale.appLocale
    formatter.dateFormat = "EEEE, d. MMMM yyyy"
    return formatter.string(from: date).sentenceCased()
  }
}
