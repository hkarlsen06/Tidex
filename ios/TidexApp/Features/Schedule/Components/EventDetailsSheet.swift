import SwiftUI

struct EventEditResult {
  let eventId: String
  let startDate: String
  let endDate: String
  let isAllDay: Bool
  let startTime: String?
  let endTime: String?
  let note: String
  let notificationMinutesArray: [Int]?
  let notificationAnchorTime: String?
}

/// The two lines under the event title: which day(s), and what time.
struct EventDetailsScheduleSummary: Equatable {
  let dateText: String
  let timeText: String
}

enum EventDetailsSummaryBuilder {
  static func scheduleSummary(for event: EventRow) -> EventDetailsScheduleSummary {
    let dateText =
      event.start_date == event.end_date
      ? EventSheetFormatter.longDate(event.start_date)
      : EventSheetFormatter.dateRange(from: event.start_date, to: event.end_date)

    guard !event.is_all_day, let start = event.start_time, let end = event.end_time else {
      return EventDetailsScheduleSummary(
        dateText: dateText,
        timeText: String(localized: .addShiftEventAllDay)
      )
    }

    return EventDetailsScheduleSummary(
      dateText: dateText,
      timeText: ShiftCardFormatter.localizedTimeRange(
        start: start,
        end: end,
        locale: Locale.appLocale,
        separator: " – "
      )
    )
  }
}

/// Explains why an event with an overnight time range can't be saved.
struct EventTimeRangeHint: View {
  var body: some View {
    Text(.addShiftSubmitRequirementsEventSameDay)
      .font(.tidexCaptionRegular)
      .foregroundColor(.tidexError)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("event.time-range-hint")
  }
}

struct EventDetailsSheet: View {
  let event: EventRow
  let onDelete: (() -> Void)?
  let onUpdate: ((EventEditResult) async throws -> Void)?
  let onInlineReminderUpdate: ((EventEditResult) async throws -> Void)?
  let showsCalendarSubscriptionCTA: Bool
  let onShowInCalendarRequested: (() -> Void)?
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
  @State private var reminderTimes: [Int] = []
  @State private var reminderAnchorTime: Date?
  @State private var focusedTimeField: TimeInputField?
  @State private var errorMessage: String?
  @State private var isSaving = false
  @State private var showingCalendarSubscriptionConfirmation = false
  @State private var isResettingDraft = false
  @State private var lastSavedReminderTimes: [Int] = []
  @State private var lastSavedReminderAnchorTime: Date?
  @FocusState private var isTitleFieldFocused: Bool

  private let inlineReminderSaveDelayNanoseconds: UInt64 = 300_000_000

  init(
    event: EventRow,
    onDelete: (() -> Void)?,
    onUpdate: ((EventEditResult) async throws -> Void)?,
    onInlineReminderUpdate: ((EventEditResult) async throws -> Void)? = nil,
    showsCalendarSubscriptionCTA: Bool = false,
    onShowInCalendarRequested: (() -> Void)? = nil,
    startInEditMode: Bool = false
  ) {
    self.event = event
    self.onDelete = onDelete
    self.onUpdate = onUpdate
    self.onInlineReminderUpdate = onInlineReminderUpdate
    self.showsCalendarSubscriptionCTA = showsCalendarSubscriptionCTA
    self.onShowInCalendarRequested = onShowInCalendarRequested
    self.startInEditMode = startInEditMode
  }

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

  /// Both times are set, but the end isn't after the start on the same day.
  private var showsTimeRangeHint: Bool {
    normalizedStartTimeString != nil && normalizedEndTimeString != nil && !isTimeRangeValid
  }

  private var canSave: Bool {
    guard !trimmedNote.isEmpty else { return false }
    if isAllDay {
      return eventEndDate >= eventStartDate && hasValidReminderConfiguration
    }
    return isTimeRangeValid && hasValidReminderConfiguration
  }

  private var canEditReminderSettings: Bool {
    !EventReminderPlanner.hasEventPassed(event)
  }

  private var hasValidReminderConfiguration: Bool {
    guard isAllDay, !reminderTimes.isEmpty else { return true }
    return reminderAnchorTime != nil
  }

  private var scheduleSummary: EventDetailsScheduleSummary {
    EventDetailsSummaryBuilder.scheduleSummary(for: event)
  }

  var body: some View {
    NavigationStack {
      navigationContent
        .onChange(of: eventStartDate) { _, newValue in
          handleStartDateChanged(newValue)
        }
        .onChange(of: eventDate) { _, newValue in
          handleEventDateChanged(newValue)
        }
        .onChange(of: reminderTimes) { _, _ in
          scheduleInlineReminderSaveIfNeeded()
        }
        .onChange(of: reminderAnchorTime) { _, _ in
          scheduleInlineReminderSaveIfNeeded()
        }
        .confirmationDialog(
          String(localized: .calendarSubscriptionDetailConfirmationTitle),
          isPresented: $showingCalendarSubscriptionConfirmation,
          titleVisibility: .visible
        ) {
          Button(String(localized: .commonContinue)) {
            onShowInCalendarRequested?()
          }
          Button(String(localized: .commonCancel), role: .cancel) {}
        } message: {
          Text(.calendarSubscriptionDetailConfirmationMessage)
        }
    }
  }

  private var navigationContent: some View {
    scrollContent
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .addShiftEventNoteTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbarContent }
      .onAppear {
        resetDraft()
        isEditing = startInEditMode
      }
      .onDisappear {
        reminderAutosaveTask?.cancel()
      }
      .onChange(of: isEditing) { _, newValue in
        if newValue {
          reminderAutosaveTask?.cancel()
        } else {
          isTitleFieldFocused = false
        }
      }
      .onChange(of: isAllDay) { _, newValue in
        handleAllDayChanged(newValue)
      }
  }

  private var scrollContent: some View {
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

        if !isEditing, onUpdate != nil {
          DetailSheetActionButton(
            title: String(localized: .shiftsActionsEdit),
            systemImage: "pencil",
            style: .primary
          ) {
            beginEditing()
          }
        }
      }
      .padding(Spacing.mlg)
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      if isEditing {
        Button(String(localized: .commonCancel)) {
          resetDraft()
          withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
          }
        }
        .foregroundColor(.tidexTextSecondary)
      } else if let onDelete {
        Button(role: .destructive) {
          onDelete()
        } label: {
          Image(systemName: "trash")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexError)
        }
        .accessibilityLabel(Text(.eventsDeleteButton))
      }
    }

    ToolbarItem(placement: .topBarTrailing) {
      if isEditing {
        Button(String(localized: .commonSave)) {
          triggerSave()
        }
        .font(.tidexButton)
        .foregroundColor(canSave ? .tidexBlue : .tidexTextMuted)
        .disabled(!canSave || isSaving)
      } else {
        Button(String(localized: .commonDone)) {
          dismiss()
        }
        .font(.tidexButton)
        .foregroundColor(.tidexBlue)
      }
    }
  }

  private func handleStartDateChanged(_ newValue: Date) {
    if isAllDay, eventEndDate < newValue {
      eventEndDate = newValue
    }
    if !isAllDay {
      eventDate = newValue
      eventEndDate = newValue
    }
  }

  private func handleEventDateChanged(_ newValue: Date) {
    if !isAllDay {
      eventStartDate = newValue
      eventEndDate = newValue
    }
  }

  private func handleAllDayChanged(_ newValue: Bool) {
    if newValue {
      eventStartDate = eventDate
      if eventEndDate < eventStartDate {
        eventEndDate = eventStartDate
      }
      editedStartTime = nil
      editedEndTime = nil
      if !reminderTimes.isEmpty, reminderAnchorTime == nil {
        reminderAnchorTime = EventSheetFormatter.date(from: "09:00")
      }
    } else {
      eventDate = eventStartDate
      eventEndDate = eventStartDate
      reminderAnchorTime = nil
    }
  }

  @State private var reminderAutosaveTask: Task<Void, Never>?

  private var detailsContent: some View {
    VStack(spacing: Spacing.md) {
      headerCard

      remindersCard(isEditable: canEditReminderSettings, showsPastHint: !canEditReminderSettings)

      if showsCalendarSubscriptionCTA {
        calendarSubscriptionRow
      }
    }
  }

  /// What the event is and when, in one glance. Tapping it opens the editor.
  private var headerCard: some View {
    Button {
      beginEditing()
    } label: {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text(event.note)
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: Spacing.xs) {
          headerLine(systemImage: "calendar", text: scheduleSummary.dateText)
          headerLine(systemImage: "clock", text: scheduleSummary.timeText)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.lg)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))
    }
    .buttonStyle(.plain)
  }

  private func headerLine(systemImage: String, text: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: systemImage)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .frame(width: Spacing.iconSize)
        .accessibilityHidden(true)

      Text(text)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var calendarSubscriptionRow: some View {
    Button {
      showingCalendarSubscriptionConfirmation = true
    } label: {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "calendar.badge.clock")
          .font(.tidexBody)
          .foregroundColor(.tidexTextSecondary)
          .frame(width: Spacing.iconSize)
          .accessibilityHidden(true)

        Text(.calendarSubscriptionDetailCta)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.leading)

        Spacer(minLength: Spacing.xs)

        Image(systemName: "chevron.right")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextMuted)
          .flipsForRightToLeftLayoutDirection(true)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .frame(minHeight: 44)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))
    }
    .buttonStyle(.plain)
  }

  private var editorContent: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      titleEditorSection

      scheduleEditorSection

      remindersCard(isEditable: canEditReminderSettings, showsPastHint: !canEditReminderSettings)
    }
  }

  private var titleEditorSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.addShiftEventNoteTitle)
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexTextMuted)

      TextField(
        String(localized: .addShiftSubmitRequirementsEventNote),
        text: $editedNote,
        axis: .vertical
      )
      .focused($isTitleFieldFocused)
      .textFieldStyle(.plain)
      .font(.tidexBodyLarge)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(2...5)
      .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .fill(Color.tidexSurfaceSecondary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .stroke(
            isTitleFieldFocused ? Color.tidexBlue.opacity(0.45) : Color.tidexBorder, lineWidth: 1)
      )
    }
    .contentShape(Rectangle())
    .onTapGesture {
      focusedTimeField = nil
      isTitleFieldFocused = true
    }
  }

  private var scheduleEditorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()
        .background(Color.tidexBorder)

      allDayToggleRow

      Divider()
        .background(Color.tidexBorder)

      Group {
        if isAllDay {
          VStack(alignment: .leading, spacing: Spacing.sm) {
            dateEditor(
              title: String(localized: .addShiftEventStartDate), selection: $eventStartDate)
            dateEditor(title: String(localized: .addShiftEventEndDate), selection: $eventEndDate)
            eventRangeSummary
          }
        } else {
          timedEventEditor
        }
      }
      .padding(.top, Spacing.md)
    }
    .simultaneousGesture(
      TapGesture().onEnded {
        isTitleFieldFocused = false
      }
    )
  }

  private var timedEventEditor: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      dateEditor(title: String(localized: .addShiftEventDate), selection: $eventDate)

      TimeRangePicker(
        startTime: $editedStartTime,
        endTime: $editedEndTime,
        scrollProxy: nil,
        scrollId: "event-details-time-range",
        focusedFieldBinding: $focusedTimeField
      )

      if showsTimeRangeHint {
        EventTimeRangeHint()
      }
    }
  }

  private var allDayToggleRow: some View {
    HStack(alignment: .center, spacing: Spacing.sm) {
      Text(.addShiftEventAllDay)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Spacer(minLength: Spacing.sm)

      Toggle(String(localized: .addShiftEventAllDay), isOn: $isAllDay)
        .labelsHidden()
        .tint(.tidexTextPrimary)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xsm)
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
      .tint(.tidexTextPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Spacing.sm)
  }

  private var eventRangeSummary: some View {
    HStack(spacing: Spacing.xxxs) {
      Image(systemName: "arrow.left.and.right")
        .font(.tidexMicro)
      Text(editorRangeSummaryText)
        .font(.tidexMicro)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundColor(.tidexTextMuted)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func remindersCard(isEditable: Bool, showsPastHint: Bool) -> some View {
    EventReminderEditorSection(
      reminderTimes: $reminderTimes,
      anchorTime: $reminderAnchorTime,
      isAllDay: isAllDay,
      isEditable: isEditable,
      showsPastEventHint: showsPastHint
    )
    .padding(Spacing.lg)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }

  private var editorRangeSummaryText: String {
    if Calendar.gregorianCurrent.isDate(eventStartDate, inSameDayAs: eventEndDate) {
      return eventStartDate.formatted(
        .dateTime.weekday(.wide).day().month(.wide).calendar(.gregorian))
    }

    let format = Date.FormatStyle.dateTime.day().month(.abbreviated).calendar(.gregorian)
    return "\(eventStartDate.formatted(format)) - \(eventEndDate.formatted(format))"
  }

  private func errorBanner(message: String) -> some View {
    Text(message)
      .font(.tidexSubheadline)
      .foregroundColor(.tidexError)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexError.opacity(0.08))
      )
  }

  private func beginEditing() {
    focusedTimeField = nil
    isTitleFieldFocused = false

    withAnimation(.easeInOut(duration: 0.2)) {
      isEditing = true
    }
  }

  private func resetDraft() {
    isResettingDraft = true
    reminderAutosaveTask?.cancel()
    editedNote = event.note
    isAllDay = event.is_all_day
    eventDate = Date.fromISODateString(event.start_date) ?? Date()
    eventStartDate = Date.fromISODateString(event.start_date) ?? eventDate
    eventEndDate = Date.fromISODateString(event.end_date) ?? eventStartDate
    editedStartTime = EventSheetFormatter.date(from: event.start_time)
    editedEndTime = EventSheetFormatter.date(from: event.end_time)
    reminderTimes = LocalEvent.normalizedReminderMinutes(event.notification_minutes_array)
    reminderAnchorTime = EventSheetFormatter.date(from: event.notification_anchor_time)
    lastSavedReminderTimes = reminderTimes
    lastSavedReminderAnchorTime = reminderAnchorTime
    errorMessage = nil
    isResettingDraft = false
  }

  private func triggerSave() {
    Task {
      await saveChanges(dismissOnSuccess: true, usesInlineHandler: false)
    }
  }

  private func saveChanges(dismissOnSuccess: Bool, usesInlineHandler: Bool) async {
    guard canSave else {
      errorMessage = String(localized: .eventsValidationMessage)
      return
    }

    let updateHandler = usesInlineHandler ? onInlineReminderUpdate : onUpdate
    guard let updateHandler else { return }

    let result = EventEditResult(
      eventId: event.id,
      startDate: (isAllDay ? eventStartDate : eventDate).toISODateString(),
      endDate: (isAllDay ? eventEndDate : eventDate).toISODateString(),
      isAllDay: isAllDay,
      startTime: isAllDay ? nil : normalizedStartTimeString,
      endTime: isAllDay ? nil : normalizedEndTimeString,
      note: trimmedNote,
      notificationMinutesArray: reminderTimes.isEmpty ? nil : reminderTimes,
      notificationAnchorTime: isAllDay && !reminderTimes.isEmpty
        ? reminderAnchorTime?.toHourMinuteString()
        : nil
    )

    isSaving = true
    errorMessage = nil

    do {
      try await updateHandler(result)
      lastSavedReminderTimes = reminderTimes
      lastSavedReminderAnchorTime = reminderAnchorTime
      if dismissOnSuccess {
        dismiss()
      }
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }

    isSaving = false
  }

  private func scheduleInlineReminderSaveIfNeeded() {
    guard !isEditing else { return }
    guard !isResettingDraft else { return }
    guard canEditReminderSettings else { return }
    guard onInlineReminderUpdate != nil else { return }

    let normalizedTimes = LocalEvent.normalizedReminderMinutes(reminderTimes)
    if reminderTimes != normalizedTimes {
      reminderTimes = normalizedTimes
      return
    }

    guard
      normalizedTimes != lastSavedReminderTimes || reminderAnchorTime != lastSavedReminderAnchorTime
    else { return }

    reminderAutosaveTask?.cancel()
    reminderAutosaveTask = Task {
      do {
        try await Task.sleep(nanoseconds: inlineReminderSaveDelayNanoseconds)
        guard !Task.isCancelled else { return }
        await saveChanges(dismissOnSuccess: false, usesInlineHandler: true)
      } catch {
      }
    }
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
    var calendar = Calendar.gregorianCurrent
    calendar.timeZone = Date.localTimeZone
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = is24 ? 0 : hour
    components.minute = minute
    return calendar.date(from: components)
  }

  static func longDate(_ isoDate: String) -> String {
    guard let date = Date.fromISODateString(isoDate) else { return isoDate }
    return date.formatted(
      .dateTime.weekday(.wide).day().month(.wide).year().locale(.appLocale)
    ).sentenceCased()
  }

  /// A multi-day span on one line, like "Mon 20 – Wed 22 April 2026".
  static func dateRange(from startISO: String, to endISO: String) -> String {
    guard
      let start = Date.fromISODateString(startISO),
      let end = Date.fromISODateString(endISO),
      start < end
    else {
      return longDate(startISO)
    }

    let style = Date.IntervalFormatStyle(locale: .appLocale, calendar: .gregorianCurrent)
      .weekday(.abbreviated).day().month(.wide).year()
    return (start..<end).formatted(style).sentenceCased()
  }
}
