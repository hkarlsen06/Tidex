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

struct EventDetailsSummaryRow: Equatable {
  let title: String
  let value: String
}

struct EventDetailsScheduleSummary: Equatable {
  let rows: [EventDetailsSummaryRow]
  let footerText: String
  let footerIcon: String
}

enum EventDetailsSummaryBuilder {
  static func scheduleSummary(for event: EventRow) -> EventDetailsScheduleSummary {
    let formattedStartDate = EventSheetFormatter.longDate(event.start_date)
    let formattedEndDate = EventSheetFormatter.longDate(event.end_date)
    let spansMultipleDays = event.start_date != event.end_date

    if event.is_all_day {
      if spansMultipleDays {
        return EventDetailsScheduleSummary(
          rows: [
            EventDetailsSummaryRow(
              title: String(localized: .addShiftEventStartDate),
              value: formattedStartDate
            ),
            EventDetailsSummaryRow(
              title: String(localized: .addShiftEventEndDate),
              value: formattedEndDate
            ),
          ],
          footerText: String(localized: .addShiftEventAllDay),
          footerIcon: "calendar"
        )
      }

      return EventDetailsScheduleSummary(
        rows: [
          EventDetailsSummaryRow(
            title: String(localized: .addShiftEventDate),
            value: formattedStartDate
          )
        ],
        footerText: String(localized: .addShiftEventAllDay),
        footerIcon: "calendar"
      )
    }

    let footerText: String = {
      guard let start = event.start_time, let end = event.end_time else {
        return String(localized: .addShiftEventAllDay)
      }

      return ShiftCardFormatter.localizedTimeRange(
        start: start,
        end: end,
        locale: Locale.appLocale,
        separator: " – "
      )
    }()

    if spansMultipleDays {
      return EventDetailsScheduleSummary(
        rows: [
          EventDetailsSummaryRow(
            title: String(localized: .addShiftEventStartDate),
            value: formattedStartDate
          ),
          EventDetailsSummaryRow(
            title: String(localized: .addShiftEventEndDate),
            value: formattedEndDate
          ),
        ],
        footerText: footerText,
        footerIcon: "clock"
      )
    }

    return EventDetailsScheduleSummary(
      rows: [
        EventDetailsSummaryRow(
          title: String(localized: .addShiftEventDate),
          value: formattedStartDate
        )
      ],
      footerText: footerText,
      footerIcon: "clock"
    )
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
  @State private var successMessage: String?
  @State private var isSaving = false
  @State private var showingCalendarSubscriptionConfirmation = false
  @State private var isResettingDraft = false
  @State private var lastSavedReminderTimes: [Int] = []
  @State private var lastSavedReminderAnchorTime: Date?
  @State private var shouldFocusTitleWhenEditing = false
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

          if let successMessage {
            successBanner(message: successMessage)
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
      .onAppear {
        resetDraft()
        shouldFocusTitleWhenEditing = startInEditMode
        isEditing = startInEditMode
      }
      .onDisappear {
        reminderAutosaveTask?.cancel()
      }
      .onChange(of: isEditing) { _, newValue in
        if newValue {
          reminderAutosaveTask?.cancel()
        }
        guard newValue else {
          isTitleFieldFocused = false
          shouldFocusTitleWhenEditing = false
          return
        }

        if shouldFocusTitleWhenEditing {
          DispatchQueue.main.async {
            isTitleFieldFocused = true
          }
        }
      }
      .onChange(of: isAllDay) { _, newValue in
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
      .onChange(of: reminderTimes) { _, _ in
        scheduleInlineReminderSaveIfNeeded()
      }
      .onChange(of: reminderAnchorTime) { _, _ in
        scheduleInlineReminderSaveIfNeeded()
      }
      .confirmationDialog(
        String(localized: "calendar.subscription.detail.confirmation.title"),
        isPresented: $showingCalendarSubscriptionConfirmation,
        titleVisibility: .visible
      ) {
        Button(String(localized: .commonContinue)) {
          onShowInCalendarRequested?()
        }
        Button(String(localized: .commonCancel), role: .cancel) {}
      } message: {
        Text("calendar.subscription.detail.confirmation.message")
      }
    }
  }

  @State private var reminderAutosaveTask: Task<Void, Never>?

  private var detailsContent: some View {
    VStack(spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(.addShiftEventNoteTitle)
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
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
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))
      .onTapGesture {
        beginEditing(focusTitle: true)
      }

      VStack(spacing: Spacing.sm) {
        ForEach(Array(scheduleSummary.rows.enumerated()), id: \.offset) { index, row in
          detailRow(title: row.title, value: row.value)

          if index < scheduleSummary.rows.count - 1 {
            Divider()
              .background(Color.tidexBorder)
          }
        }

        Divider()
          .background(Color.tidexBorder)

        scheduleFooter
      }
      .padding(Spacing.lg)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))
      .onTapGesture {
        beginEditing(focusTitle: false)
      }

      remindersCard(isEditable: canEditReminderSettings, showsPastHint: !canEditReminderSettings)
    }
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
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)

      TextField(
        String(localized: "addShift.submitRequirements.eventNote", table: "Localizable"),
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
          VStack(alignment: .leading, spacing: Spacing.md) {
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
      .padding(.top, Spacing.md)
    }
    .simultaneousGesture(
      TapGesture().onEnded {
        isTitleFieldFocused = false
      }
    )
  }

  private var allDayToggleRow: some View {
    HStack(alignment: .center, spacing: Spacing.sm) {
      Text(.addShiftEventAllDay)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Spacer(minLength: Spacing.sm)

      Toggle(String(localized: .addShiftEventAllDay), isOn: $isAllDay)
        .labelsHidden()
        .tint(.tidexBlue)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xsm)
  }

  private var actionButtons: some View {
    VStack(spacing: Spacing.md) {
      if !isEditing {
        if showsCalendarSubscriptionCTA {
          DetailSheetActionButton(
            title: String(localized: "calendar.subscription.detail.cta"),
            systemImage: "calendar.badge.clock",
            style: .primary
          ) {
            showingCalendarSubscriptionConfirmation = true
          }
        }

        VStack(spacing: Spacing.sm) {
          DetailSheetActionButton(
            title: String(localized: .shiftsActionsEdit),
            style: .secondary
          ) {
            beginEditing(focusTitle: true)
          }

          deleteActionButton
        }
      } else {
        deleteActionButton
      }
    }
  }

  private var deleteActionButton: some View {
    DetailSheetActionButton(
      title: String(localized: .eventsDeleteButton),
      style: .destructive
    ) {
      onDelete?()
    }
  }

  private var scheduleFooter: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: scheduleSummary.footerIcon)
        .font(.tidexFootnote)
      Text(scheduleSummary.footerText)
        .font(.tidexSubheadline)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
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
    if Calendar.current.isDate(eventStartDate, inSameDayAs: eventEndDate) {
      return eventStartDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    return
      "\(eventStartDate.formatted(.dateTime.day().month(.abbreviated))) - \(eventEndDate.formatted(.dateTime.day().month(.abbreviated)))"
  }

  private func errorBanner(message: String) -> some View {
    statusBanner(message: message, color: .red)
  }

  private func successBanner(message: String) -> some View {
    statusBanner(message: message, color: .tidexSuccess)
  }

  private func statusBanner(message: String, color: Color) -> some View {
    Text(message)
      .font(.tidexSubheadline)
      .foregroundColor(color)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(color.opacity(0.08))
      )
  }

  private func beginEditing(focusTitle: Bool) {
    shouldFocusTitleWhenEditing = focusTitle
    focusedTimeField = nil

    if !focusTitle {
      isTitleFieldFocused = false
    }

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
    successMessage = nil
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
