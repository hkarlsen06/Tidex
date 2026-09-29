import SwiftUI

// MARK: - Event Content

struct EventContent: View {
  @Bindable var viewModel: AddShiftViewModel
  @Binding var focusedTimeField: TimeInputField?
  @FocusState private var isTitleFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      titleSection

      scheduleSection

      remindersSection
    }
  }

  private var titleSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.addShiftEventNoteTitle)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)

      TextField(
        String(localized: .addShiftSubmitRequirementsEventNote),
        text: $viewModel.eventNote,
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
      .overlay {
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .stroke(
            isTitleFieldFocused ? Color.tidexBlue.opacity(0.45) : Color.tidexBorder, lineWidth: 1)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      focusedTimeField = nil
      isTitleFieldFocused = true
    }
  }

  private var scheduleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()
        .background(Color.tidexBorder)

      allDayToggleRow

      Divider()
        .background(Color.tidexBorder)

      scheduleDetails
    }
  }

  private var scheduleDetails: some View {
    VStack(spacing: Spacing.md) {
      AddShiftCalendarView(
        viewModel: viewModel,
        selectedDatesOverride: viewModel.eventCalendarSelectedDates,
        previewEarningsOverride: [:],
        onToggleDateOverride: viewModel.toggleEventCalendarDate,
        showSelectionCheckmark: false,
        selectionEmphasis: .subtle
      )
      .monthSwipeGesture(
        onSwipeLeft: { viewModel.goToNextMonth() },
        onSwipeRight: { viewModel.goToPreviousMonth() },
        isEnabled: true
      )
      .simultaneousGesture(
        TapGesture().onEnded {
          isTitleFieldFocused = false
        }
      )

      if viewModel.isEventAllDay {
        eventRangeSummary
      } else {
        eventTimeControls
      }
    }
    .padding(.top, Spacing.md)
  }

  @ViewBuilder
  private var eventTimeControls: some View {
    TimeRangePicker(
      startTime: $viewModel.startTime,
      endTime: $viewModel.endTime,
      scrollProxy: nil,
      scrollId: "eventTimePicker",
      focusedFieldBinding: $focusedTimeField,
      chipsAboveInputs: true
    )

    if viewModel.eventTimesCrossMidnight {
      EventTimeRangeHint()
        .padding(.horizontal, Spacing.sm)
    }
  }

  private var allDayToggleRow: some View {
    HStack(alignment: .center, spacing: Spacing.sm) {
      Text(.addShiftEventAllDay)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Spacer(minLength: Spacing.sm)

      Toggle(String(localized: .addShiftEventAllDay), isOn: $viewModel.isEventAllDay)
        .labelsHidden()
        .tint(.tidexBlue)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xsm)
  }

  private var eventRangeSummary: some View {
    HStack(spacing: Spacing.xxxs) {
      Image(systemName: "arrow.left.and.right")
        .font(.tidexMicro)
      Text(rangeSummaryText)
        .font(.tidexMicro)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundColor(.tidexTextMuted)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var rangeSummaryText: String {
    if Calendar.gregorianCurrent.isDate(
      viewModel.eventStartDate, inSameDayAs: viewModel.eventEndDate)
    {
      return viewModel.eventStartDate.formatted(
        .dateTime.weekday(.wide).day().month(.wide).calendar(.gregorian))
    }

    let format = Date.FormatStyle.dateTime.day().month(.abbreviated).calendar(.gregorian)
    return
      "\(viewModel.eventStartDate.formatted(format)) - \(viewModel.eventEndDate.formatted(format))"
  }

  private var remindersSection: some View {
    EventReminderEditorSection(
      reminderTimes: $viewModel.eventReminderTimes,
      anchorTime: $viewModel.eventReminderAnchorTime,
      isAllDay: viewModel.isEventAllDay,
      isEditable: true,
      showsPastEventHint: false
    )
    .padding(Spacing.lg)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }
}
