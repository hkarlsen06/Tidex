import SwiftUI

/// Sheet view displaying detailed information about a shift
/// Shows date, time, hours, earnings breakdown, and actions
/// Supports edit mode for modifying date and times
/// Result of a shift edit operation
struct ShiftEditResult {
  let shiftId: String
  let shiftDate: String  // ISO format YYYY-MM-DD
  let startTime: String  // HH:mm format
  let endTime: String  // HH:mm format
  let isVirtualShiftConversion: Bool  // If true, exclude from recurring and create new shift
  let recurringId: String?  // The recurring shift ID if converting virtual shift
  let originalDate: String  // Original date (for exclusion when converting virtual)
  let note: String?
  let noteWasEdited: Bool
  /// Custom supplements for this shift. nil = no change, empty rules = clear supplements
  let customSupplements: CustomSupplementsData?

  init(
    shiftId: String,
    shiftDate: String,
    startTime: String,
    endTime: String,
    isVirtualShiftConversion: Bool,
    recurringId: String?,
    originalDate: String,
    note: String? = nil,
    noteWasEdited: Bool = false,
    customSupplements: CustomSupplementsData? = nil
  ) {
    self.shiftId = shiftId
    self.shiftDate = shiftDate
    self.startTime = startTime
    self.endTime = endTime
    self.isVirtualShiftConversion = isVirtualShiftConversion
    self.recurringId = recurringId
    self.originalDate = originalDate
    self.note = note
    self.noteWasEdited = noteWasEdited
    self.customSupplements = customSupplements
  }
}

enum ShiftSaveError: Error, LocalizedError {
  case alreadyInProgress
  case invalidDate
  case missingRecurringInfo
  case unavailable

  var errorDescription: String? {
    switch self {
    case .alreadyInProgress:
      return String(localized: .shiftsSaveErrorInProgress)
    case .invalidDate:
      return String(localized: .shiftsSaveErrorInvalidDate)
    case .missingRecurringInfo:
      return String(localized: .shiftsSaveErrorMissingRecurringInfo)
    case .unavailable:
      return String(localized: .shiftsSaveErrorUnavailable)
    }
  }
}

enum ShiftPauseEditTarget: Equatable {
  case standalone(shiftId: String)
  case recurringOccurrence(recurringId: String, date: String)
}

struct ShiftPauseEditResult: Equatable {
  let target: ShiftPauseEditTarget
  let customPauseWindows: CustomPauseWindows?
}

struct ShiftDetailsSheet: View {
  let shift: ShiftWithComputations
  /// Job name to display in the header badge (only set when user has multiple jobs)
  let jobName: String?
  /// Job color hex for the badge (e.g. "#3B82F6")
  let jobColorHex: String?
  let onDelete: (() -> Void)?
  let onUpdate: ((ShiftEditResult) async throws -> Void)?
  let onUpdatePause: ((ShiftPauseEditResult) -> Void)?
  let onEditRecurring: ((String) -> Void)?  // Callback with recurring shift ID
  let showsCalendarSubscriptionCTA: Bool
  let onShowInCalendarRequested: (() -> Void)?
  var onSendToChatCompleted: ((SendShiftToChatResult) -> Void)?
  let snapshotShareContext: ShiftSnapshotShareContext
  /// Tariff supplement rules from the applicable snapshot (used for supplements editor)
  let tariffRules: [SupplementRule]

  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.userCurrency) private var currency
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.dismiss) private var dismiss

  // MARK: - Edit Mode State

  /// Whether the sheet is in edit mode
  @State private var isEditing = false

  /// Whether to start in edit mode (passed from parent)
  var startInEditMode: Bool = false

  /// Edited date (ISO format YYYY-MM-DD)
  @State private var editedDate: Date = Date()

  /// Edited start time
  @State private var editedStartTime: Date?

  /// Edited end time
  @State private var editedEndTime: Date?

  /// Which time input field is focused (for TimeRangePicker)
  @State private var focusedTimeField: TimeInputField?

  /// Whether the note editor is focused
  @FocusState private var isNoteFieldFocused: Bool

  /// Edited custom supplements (nil = unchanged, set to clear or modify)
  @State private var editedSupplements: CustomSupplementsData?

  /// Whether supplements were edited (to track changes)
  @State private var supplementsWereEdited = false

  /// Edited note text
  @State private var editedNote = ""

  /// Whether note was edited (to support explicit clear)
  @State private var noteWasEdited = false

  /// Optimistic note value used when a note-only save keeps the sheet open
  @State private var optimisticNoteOverride: String?

  /// Whether the optimistic note override should be used
  @State private var hasOptimisticNoteOverride = false

  /// Whether currently saving
  @State private var isSaving = false

  /// Error message to display
  @State private var errorMessage: String?

  /// Whether showing the supplements editor sheet
  @State private var showingSupplementsEditor = false

  /// Whether showing the pause editor sheet
  @State private var showingPauseEditor = false

  /// Whether the break deduction breakdown is expanded
  @State private var isBreakDeductionExpanded = false

  /// Whether the supplement breakdown is expanded
  @State private var isSupplementBreakdownExpanded = false

  /// Whether showing the share destination picker
  @State private var showingShareDestinationPicker = false

  /// Whether showing the image share options dialog
  @State private var showingImageShareOptions = false

  /// Whether showing the send-to-chat recipient picker
  @State private var showingSendToChatSheet = false
  @State private var showingCalendarSubscriptionConfirmation = false

  /// Image to share (rendered from ShareableShiftCard)
  @State private var shareImage: UIImage?

  /// URL of the temporary image file for sharing
  @State private var shareImageURL: URL?

  /// Haptic feedback generator
  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

  // MARK: - Computed Properties

  private var isVirtualShift: Bool {
    shift.isVirtual
  }

  /// Whether editing is allowed
  /// All shifts can be edited - virtual shifts will be converted to regular shifts
  private var canEditTimes: Bool {
    true
  }

  /// Initialize the edit mode from the passed parameter
  init(
    shift: ShiftWithComputations,
    jobName: String? = nil,
    jobColorHex: String? = nil,
    onDelete: (() -> Void)? = nil,
    onUpdate: ((ShiftEditResult) async throws -> Void)? = nil,
    onUpdatePause: ((ShiftPauseEditResult) -> Void)? = nil,
    onEditRecurring: ((String) -> Void)? = nil,
    showsCalendarSubscriptionCTA: Bool = false,
    onShowInCalendarRequested: (() -> Void)? = nil,
    onSendToChatCompleted: ((SendShiftToChatResult) -> Void)? = nil,
    snapshotShareContext: ShiftSnapshotShareContext = .own,
    startInEditMode: Bool = false,
    tariffRules: [SupplementRule] = []
  ) {
    self.shift = shift
    self.jobName = jobName
    self.jobColorHex = jobColorHex
    self.onDelete = onDelete
    self.onUpdate = onUpdate
    self.onUpdatePause = onUpdatePause
    self.onEditRecurring = onEditRecurring
    self.showsCalendarSubscriptionCTA = showsCalendarSubscriptionCTA
    self.onShowInCalendarRequested = onShowInCalendarRequested
    self.onSendToChatCompleted = onSendToChatCompleted
    self.snapshotShareContext = snapshotShareContext
    self.startInEditMode = startInEditMode
    self.tariffRules = tariffRules
  }

  private var formattedDate: String {
    guard let date = Date.fromISODateString(shift.shiftDate) else {
      return shift.shiftDate
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.appLocale
    formatter.dateFormat = "EEEE, d. MMMM yyyy"
    return formatter.string(from: date).sentenceCased()
  }

  private var formattedTimeRange: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  private var formattedHours: String {
    let hoursLabel = String(localized: .commonHours)
    let formatter = FormatterCache.numberFormatter(includeDecimals: true, locale: Locale.appLocale)
    let hoursValue =
      formatter.string(from: NSNumber(value: shift.paidHours))
      ?? String(format: "%.2f", shift.paidHours)
    return "\(hoursValue) \(hoursLabel)"
  }

  private var showTaxBreakdown: Bool {
    shift.taxEnabled && shift.taxAmount > 0
  }

  /// Whether this shift has supplement pay to show breakdown
  private var hasSupplementBreakdown: Bool {
    displayedSupplementPay > 0 && !supplementSegments.isEmpty
  }

  private var hasEarningsBreakdown: Bool {
    hasSupplementBreakdown || shouldShowBreakDeductionRow
  }

  private var displayedBasePay: Double {
    shouldShowBreakDeductionRow
      ? BreakDeductionBreakdown.basePay(for: shift.computed.originalWagePeriods)
      : shift.computed.basePay
  }

  private var displayedSupplementPay: Double {
    shouldShowBreakDeductionRow
      ? BreakDeductionBreakdown.supplementPay(for: shift.computed.originalWagePeriods)
      : shift.computed.supplementPay
  }

  /// Check if shift has custom supplements (including explicitly empty rules)
  private var hasCustomSupplements: Bool {
    return shift.shift.custom_supplements != nil
  }

  private var noteBinding: Binding<String> {
    Binding(
      get: { editedNote },
      set: {
        editedNote = $0
        noteWasEdited = true
      }
    )
  }

  private var displayedNote: String? {
    hasOptimisticNoteOverride ? optimisticNoteOverride : shift.note
  }

  private var normalizedCustomPauseWindows: CustomPauseWindows? {
    PauseWindowSupport.normalize(shift.shift.custom_pause_windows)
  }

  private var hasCustomPauseWindows: Bool {
    normalizedCustomPauseWindows != nil
  }

  private var shouldShowBreakSection: Bool {
    onUpdatePause != nil || hasCustomPauseWindows || shift.computed.breakAudit.deductedHours > 0
  }

  private var shouldShowEditOptionsSection: Bool {
    canEditSupplements || canEditPauseWindows
  }

  private var canEditSupplements: Bool {
    onUpdate != nil && !tariffRules.isEmpty
  }

  private var canEditPauseWindows: Bool {
    onUpdatePause != nil
  }

  private var displayedPauseWindows: [PauseWindow] {
    if shift.computed.breakAudit.source == .customPauseWindows,
      let appliedPauseWindows = shift.computed.breakAudit.appliedPauseWindows,
      !appliedPauseWindows.isEmpty
    {
      return appliedPauseWindows
    }

    return normalizedCustomPauseWindows?.windows ?? []
  }

  private var deductedPauseMinutes: Int {
    Int((shift.computed.breakAudit.deductedHours * 60).rounded())
  }

  private var breakDeductionBreakdown: BreakDeductionBreakdown? {
    BreakDeductionBreakdown.make(
      originalPeriods: shift.computed.originalWagePeriods,
      adjustedPeriods: shift.computed.wagePeriods
    )
  }

  private var shouldShowBreakDeductionRow: Bool {
    shift.computed.breakAudit.deductedHours > 0 && breakDeductionBreakdown != nil
  }

  private var breakDeductionLabel: String {
    String(localized: .shiftsBreakDeduction)
  }

  private var breakDeductionExplanation: LocalizedStringResource {
    switch shift.computed.breakAudit.source {
    case .customPauseWindows:
      return .shiftsBreakDeductionExplanationExactPause
    case .automaticBreak:
      switch shift.computed.breakAudit.method {
      case .proportional:
        return .shiftsBreakDeductionExplanationProportional
      case .baseOnly:
        return .shiftsBreakDeductionExplanationBaseOnly
      case .endOfShift:
        return .shiftsBreakDeductionExplanationEndOfShift
      case .none:
        return .shiftsBreakDeductionExplanationGeneric
      }
    case .none:
      return .shiftsBreakDeductionExplanationGeneric
    }
  }

  private var pauseEditorButtonTitle: String {
    hasCustomPauseWindows
      ? String(localized: .shiftsPauseSectionEditWindows)
      : String(localized: .shiftsPauseSectionAddExactWindows)
  }

  private var breakSummaryText: String {
    switch shift.computed.breakAudit.source {
    case .customPauseWindows:
      return String(localized: .shiftsPauseSectionSummaryCustomOverride)
    case .automaticBreak:
      return String(localized: .shiftsPauseSectionSummaryAutomaticApplied)
    case .none:
      return hasCustomPauseWindows
        ? String(localized: .shiftsPauseSectionSummarySavedOnShift)
        : String(localized: .shiftsPauseSectionSummaryAddHint)
    }
  }

  private func pauseEditTarget() -> ShiftPauseEditTarget? {
    if let recurringId = shift.shift.recurring_id {
      return .recurringOccurrence(recurringId: recurringId, date: shift.shiftDate)
    }
    return .standalone(shiftId: shift.id)
  }

  /// Base wage rate per hour (for showing in supplement rows)
  private var baseWageRate: Double {
    guard shift.computed.paidHours > 0 else { return 0 }
    return shift.computed.basePay / shift.computed.paidHours
  }

  /// Supplement segments grouped by rate for display
  /// Groups consecutive wage periods with the same supplement rate
  private var supplementSegments: [SupplementSegment] {
    let original = shift.computed.originalWagePeriods
    let adjusted = shouldShowBreakDeductionRow ? original : shift.computed.wagePeriods

    var segments: [SupplementSegment] = []
    var i = 0

    while i < original.count {
      let period = original[i]
      // Skip periods with no supplement
      guard period.supplementRate > 0 else {
        i += 1
        continue
      }

      // Find consecutive periods with same supplement rate
      let groupStart = period.fromMin
      var groupEnd = period.toMin
      let currentRate = period.supplementRate
      var j = i + 1

      while j < original.count && original[j].supplementRate == currentRate {
        groupEnd = original[j].toMin
        j += 1
      }

      // Calculate actual paid hours for this supplement rate group from adjusted periods
      var actualHours: Double = 0
      for adj in adjusted where adj.supplementRate == currentRate {
        let overlapStart = max(adj.fromMin, groupStart)
        let overlapEnd = min(adj.toMin, groupEnd)
        if overlapEnd > overlapStart {
          actualHours += (overlapEnd - overlapStart) / 60.0
        }
      }

      if actualHours > 0 {
        segments.append(
          SupplementSegment(
            fromMin: groupStart,
            toMin: groupEnd,
            rate: currentRate,
            actualHours: actualHours
          ))
      }

      i = j
    }

    return segments
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.lg) {
          // Header with date
          headerSection

          // Time and hours (editable in edit mode)
          if isEditing {
            editableTimeSection
          } else {
            timeSection
          }

          if isEditing {
            noteEditorSection
          } else {
            noteSection
          }

          if isEditing, shouldShowEditOptionsSection {
            editOptionsSection
          }

          if !isEditing, shouldShowBreakSection {
            breakSection
          }

          // Error message
          if let error = errorMessage {
            errorBanner(message: error)
          }

          // Earnings breakdown (hidden in edit mode)
          if !isEditing {
            earningsSection
          }

          // Virtual shift indicator
          if isVirtualShift && !isEditing {
            virtualShiftBanner
          }

          // Action buttons
          if isEditing {
            editActionButtons
          } else {
            viewModeActionButtons
          }

          // Added/edited timestamps (only in view mode, for non-virtual shifts)
          if !isEditing, !isVirtualShift {
            shiftTimestampFooter(createdAt: shift.createdAt, updatedAt: shift.updatedAt)
          }
        }
        .padding(Spacing.mlg)
      }
      .background(Color.tidexBackground)
      .navigationTitle(
        isEditing
          ? String(localized: .shiftsEditTitle)
          : String(localized: .shiftsDetailsTitle)
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if isEditing {
            Button(String(localized: .commonCancel)) {
              cancelEditing()
            }
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextSecondary)
          } else {
            Button {
              impactHaptic.impactOccurred()
              if canSendShiftSnapshots {
                showingShareDestinationPicker = true
              } else {
                showingImageShareOptions = true
              }
            } label: {
              Image(systemName: "square.and.arrow.up")
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexBlue)
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if isEditing {
            Button(String(localized: .commonSave)) {
              saveChanges()
            }
            .font(.tidexButton)
            .foregroundColor(.tidexBlue)
            .disabled(isSaving || !hasChanges)
            .opacity(isSaving || !hasChanges ? 0.5 : 1)
          } else {
            Button(String(localized: .commonDone)) {
              dismiss()
            }
            .font(.tidexButton)
            .foregroundColor(.tidexBlue)
          }
        }
      }
    }
    .onAppear {
      initializeEditState()
      if startInEditMode {
        isEditing = true
      }
    }
    .onChange(of: shift.note) { _, newValue in
      if hasOptimisticNoteOverride, newValue == optimisticNoteOverride {
        hasOptimisticNoteOverride = false
        optimisticNoteOverride = nil
      }
    }
    .interactiveDismissDisabled(isEditing && hasChanges)
    .sheet(isPresented: $showingShareDestinationPicker) {
      ShareDestinationSheet(
        onShareAsImage: {
          showingShareDestinationPicker = false
          showingImageShareOptions = true
        },
        onShareInChat: {
          showingShareDestinationPicker = false
          showingSendToChatSheet = true
        }
      )
      .presentationDetents([.height(250)])
      .presentationDragIndicator(.visible)
    }
    .sheet(
      isPresented: $showingImageShareOptions,
      onDismiss: {
        // Check if we have a pending share action
        if let url = shareImageURL {
          presentShareSheet(with: [url])
        } else if let image = shareImage {
          presentShareSheet(with: [image])
        }
      }
    ) {
      ShareOptionsSheet(
        onShowEarnings: {
          // Prepare the image first, then dismiss - share sheet shows on dismiss
          prepareShiftImage(includeEarnings: true)
          showingImageShareOptions = false
        },
        onHideEarnings: {
          // Prepare the image first, then dismiss - share sheet shows on dismiss
          prepareShiftImage(includeEarnings: false)
          showingImageShareOptions = false
        }
      )
      .presentationDetents([.height(260)])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingSupplementsEditor) {
      CustomSupplementsEditorSheet(
        shift: shift,
        currency: currency,
        tariffRules: tariffRules,
        onSave: { customSupplements in
          // Update the edited supplements state
          editedSupplements = customSupplements
          supplementsWereEdited = true
          showingSupplementsEditor = false

          // If we're not already in edit mode, immediately save with just supplements
          // (Otherwise, wait for user to click Save in edit mode)
          if !isEditing {
            guard let onUpdate else {
              errorMessage = ShiftSaveError.unavailable.localizedDescription
              return
            }

            let editResult = ShiftEditResult(
              shiftId: shift.id,
              shiftDate: shift.shiftDate,
              startTime: shift.startTime,
              endTime: shift.endTime,
              isVirtualShiftConversion: isVirtualShift,
              recurringId: shift.shift.recurring_id,
              originalDate: shift.shiftDate,
              note: noteWasEdited ? trimmedEditedNote : nil,
              noteWasEdited: noteWasEdited,
              customSupplements: customSupplements
            )
            isSaving = true
            Task {
              do {
                try await onUpdate(editResult)
                dismiss()
              } catch {
                errorMessage = ErrorTranslations.translate(error)
              }
              isSaving = false
            }
          }
        },
        onCancel: {
          showingSupplementsEditor = false
        }
      )
    }
    .sheet(isPresented: $showingPauseEditor) {
      CustomPauseWindowsEditorSheet(
        shift: shift,
        onSave: { customPauseWindows in
          showingPauseEditor = false
          guard let target = pauseEditTarget() else { return }
          onUpdatePause?(
            ShiftPauseEditResult(target: target, customPauseWindows: customPauseWindows))
          dismiss()
        },
        onCancel: {
          showingPauseEditor = false
        }
      )
    }
    .sheet(isPresented: $showingSendToChatSheet) {
      if let viewerUserId, canSendShiftSnapshots {
        SendShiftToChatSheet(
          viewerUserId: viewerUserId,
          buildDraft: makeShiftSnapshotDraft(for:),
          onCompleted: { result in
            if let onSendToChatCompleted {
              onSendToChatCompleted(result)
            } else {
              coordinator.pendingDeepLink = .friendChat(
                threadId: result.threadId,
                messageId: nil,
                senderUserId: nil,
                typingUserId: nil,
                navigationRequestId: UUID()
              )
            }
            showingSendToChatSheet = false
            dismiss()
          }
        )
      }
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

  // MARK: - Edit State Management

  /// Initialize edit state from the shift data
  private func initializeEditState() {
    // Parse shift date
    if let date = Date.fromISODateString(shift.shiftDate) {
      editedDate = date
    }

    // Parse start time
    if let startTime = parseTimeToDate(shift.startTime) {
      editedStartTime = startTime
    }

    // Parse end time
    if let endTime = parseTimeToDate(shift.endTime) {
      editedEndTime = endTime
    }

    editedNote = displayedNote ?? ""
    noteWasEdited = false
  }

  /// Parse HH:mm string to Date (using today as base)
  private func parseTimeToDate(_ timeString: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    guard let time = formatter.date(from: String(timeString.prefix(5))) else { return nil }

    // Combine with today's date
    let calendar = Calendar.current
    let now = Date()
    var components = calendar.dateComponents([.year, .month, .day], from: now)
    components.hour = calendar.component(.hour, from: time)
    components.minute = calendar.component(.minute, from: time)
    return calendar.date(from: components)
  }

  /// Format Date to HH:mm string
  private func formatTimeToString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  /// Format Date to ISO date string (YYYY-MM-DD)
  private func formatDateToISO(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  /// Check if any changes have been made
  private var hasChanges: Bool {
    guard let start = editedStartTime, let end = editedEndTime else { return false }
    let newDate = formatDateToISO(editedDate)
    let newStartTime = formatTimeToString(start)
    let newEndTime = formatTimeToString(end)

    return newDate != shift.shiftDate || newStartTime != String(shift.startTime.prefix(5))
      || newEndTime != String(shift.endTime.prefix(5)) || supplementsWereEdited || noteWasEdited
  }

  private var trimmedEditedNote: String? {
    ShiftNoteSupport.normalize(editedNote)
  }

  /// Cancel editing and reset state
  private func cancelEditing() {
    initializeEditState()
    errorMessage = nil
    isNoteFieldFocused = false
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      isEditing = false
    }
  }

  private func beginNoteEditing() {
    editedNote = displayedNote ?? ""
    noteWasEdited = false
    errorMessage = nil
    focusedTimeField = nil

    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      isEditing = true
    }

    DispatchQueue.main.async {
      isNoteFieldFocused = true
    }
  }

  /// Prepare the shift image for sharing (called before dismissing options sheet)
  @MainActor
  private func prepareShiftImage(includeEarnings: Bool) {
    // Create the shareable card view
    let shareableCard = ShareableShiftCard(
      shift: shift,
      currency: currency,
      includeEarnings: includeEarnings
    )

    // Render to image and save to temp file for better share sheet compatibility
    guard let image = shareableCard.renderAsImage(),
      let pngData = image.pngData()
    else {
      shareImage = nil
      shareImageURL = nil
      return
    }

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("shift-\(shift.id).png")

    do {
      try pngData.write(to: tempURL)
      shareImage = image
      shareImageURL = tempURL
    } catch {
      // Fallback to sharing image directly
      shareImage = image
      shareImageURL = nil
    }
  }

  /// Present the share sheet with the given items (called after options sheet dismisses)
  @MainActor
  private func presentShareSheet(with activityItems: [Any]) {
    // Clear the pending share state
    defer {
      shareImage = nil
      shareImageURL = nil
    }

    let activityVC = UIActivityViewController(
      activityItems: activityItems, applicationActivities: nil)

    // Get the root view controller and present
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = windowScene.windows.first?.rootViewController
    {
      // Find the topmost presented view controller
      var topVC = rootVC
      while let presented = topVC.presentedViewController {
        topVC = presented
      }
      // iPad requires popover configuration
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = topVC.view
        popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: 100, width: 0, height: 0)
        popover.permittedArrowDirections = .up
      }
      topVC.present(activityVC, animated: true)
    }
  }

  /// Save changes
  private func saveChanges() {
    guard !isSaving else { return }
    guard let startTime = editedStartTime, let endTime = editedEndTime else { return }
    // Validate times (basic validation)
    let newDate = formatDateToISO(editedDate)
    let newStartTime = formatTimeToString(startTime)
    let newEndTime = formatTimeToString(endTime)

    // Clear any previous error
    errorMessage = nil

    // Call the update callback
    isSaving = true
    impactHaptic.impactOccurred()

    guard let onUpdate else {
      isSaving = false
      errorMessage = ShiftSaveError.unavailable.localizedDescription
      return
    }

    let isNoteOnlySave =
      newDate == shift.shiftDate
      && newStartTime == String(shift.startTime.prefix(5))
      && newEndTime == String(shift.endTime.prefix(5))
      && !supplementsWereEdited
      && noteWasEdited

    // Create the edit result with all necessary information
    let editResult = ShiftEditResult(
      shiftId: shift.id,
      shiftDate: newDate,
      startTime: newStartTime,
      endTime: newEndTime,
      isVirtualShiftConversion: isVirtualShift,
      recurringId: shift.shift.recurring_id,
      originalDate: shift.shiftDate,
      note: noteWasEdited ? trimmedEditedNote : nil,
      noteWasEdited: noteWasEdited,
      customSupplements: supplementsWereEdited ? editedSupplements : nil
    )

    Task {
      do {
        try await onUpdate(editResult)

        if isNoteOnlySave {
          optimisticNoteOverride = trimmedEditedNote
          hasOptimisticNoteOverride = true
          editedNote = trimmedEditedNote ?? ""
          noteWasEdited = false
          isNoteFieldFocused = false
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isEditing = false
          }
        } else {
          dismiss()
        }
      } catch {
        errorMessage = ErrorTranslations.translate(error)
      }

      isSaving = false
    }
  }

  // MARK: - Sections

  private var headerSection: some View {
    VStack(spacing: Spacing.xs) {
      // Large date display
      Text(formattedDate)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)

      // Job badge (only shown when user has multiple jobs)
      if let jobName, !jobName.isEmpty {
        WorkplaceNameText(
          name: jobName,
          colorHex: jobColorHex,
          font: .tidexSubheadline,
          fallbackBadgeColor: .tidexBlue,
          badgeHorizontalPadding: Spacing.sm,
          badgeVerticalPadding: Spacing.xxxs
        )
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.xs)
  }

  private var timeSection: some View {
    VStack(spacing: Spacing.md) {
      // Section header
      HStack {
        Image(systemName: "clock")
          .foregroundColor(.tidexBlue)
        Text(.shiftsTimeSection)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      // Time details card
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.shiftsTimeRange)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
          Text(formattedTimeRange)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: Spacing.xxs) {
          Text(.shiftsDuration)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
          Text(formattedHours)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
        }
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  private var noteSection: some View {
    VStack(spacing: Spacing.md) {
      HStack(alignment: .center, spacing: Spacing.sm) {
        Image(systemName: "note.text")
          .foregroundColor(.tidexBlue)

        Text(.shiftsDetailsNoteTitle)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)

        Spacer()

        if onUpdate != nil {
          Button(
            shift.note == nil
              ? String(localized: .shiftsDetailsNoteAdd) : String(localized: .shiftsDetailsNoteEdit)
          ) {
            beginNoteEditing()
          }
          .font(.tidexFootnoteStrong)
          .foregroundColor(.tidexBlue)
        }
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        if let note = displayedNote {
          Text(note)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Text(.shiftsDetailsNotePlaceholder)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl))
      .onTapGesture {
        guard onUpdate != nil else { return }
        beginNoteEditing()
      }
    }
  }

  // MARK: - Editable Time Section

  private var editableTimeSection: some View {
    VStack(spacing: Spacing.md) {
      // Date picker row
      HStack {
        Text(.shiftsDate)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
        Spacer()
        DatePicker(
          "",
          selection: $editedDate,
          displayedComponents: .date
        )
        .labelsHidden()
        .tint(.tidexBlue)
      }

      Divider()

      // Time range picker (numeric keyboard input)
      TimeRangePicker(
        startTime: $editedStartTime,
        endTime: $editedEndTime,
        focusedFieldBinding: $focusedTimeField
      )

      // Info about cross-midnight shifts
      if isCrossMidnightShift {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "moon.fill")
            .font(.tidexCaption)
            .foregroundColor(.tidexBlue)
          Text(.shiftsCrossMidnightInfo)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
          Spacer()
        }
        .padding(.top, Spacing.xxs)
      }

      // Virtual shift info (will be converted to regular shift)
      if isVirtualShift {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "info.circle")
            .font(.tidexSubheadline)
            .foregroundColor(.tidexBlue)
          Text(.shiftsVirtualConversionInfo)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
          Spacer()
        }
        .padding(.top, Spacing.xxs)
      }
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }

  private var noteEditorSection: some View {
    VStack(spacing: Spacing.md) {
      HStack(alignment: .center, spacing: Spacing.sm) {
        Image(systemName: "note.text")
          .foregroundColor(.tidexBlue)

        Text(.shiftsDetailsNoteTitle)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)

        Spacer()
      }

      TextField(
        String(localized: .shiftsDetailsNotePlaceholder),
        text: noteBinding,
        axis: .vertical
      )
      .focused($isNoteFieldFocused)
      .textFieldStyle(.plain)
      .font(.tidexBodyMedium)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(3...8)
      .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .stroke(Color.tidexBorder, lineWidth: 1)
      )
    }
  }

  private var breakSection: some View {
    VStack(spacing: Spacing.md) {
      HStack {
        Image(systemName: "pause.circle")
          .foregroundColor(.tidexBlue)
        Text(.settingsPayEditorBreakTitle)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(breakSummaryText)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)

        if deductedPauseMinutes > 0 {
          Divider()

          HStack {
            Text(.shiftsPauseSectionDeductedLabel)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)

            Spacer()

            Text("\(deductedPauseMinutes) \(String(localized: .commonMinutesShort))")
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
          }
        }

        if !displayedPauseWindows.isEmpty {
          Divider()

          VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(.shiftsPauseSectionWindowsLabel)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)

            ForEach(Array(displayedPauseWindows.enumerated()), id: \.offset) { _, window in
              HStack {
                Text(formatPauseWindow(window))
                  .font(.tidexBodyMedium)
                  .foregroundColor(.tidexTextPrimary)
                  .environment(\.layoutDirection, .leftToRight)

                Spacer()

                Text("\(durationMinutes(for: window)) \(String(localized: .commonMinutesShort))")
                  .font(.tidexFootnote)
                  .foregroundColor(.tidexTextMuted)
              }
            }
          }
        }

        if onUpdatePause != nil {
          Divider()

          inlineEditOptionButton(
            title: pauseEditorButtonTitle,
            systemImage: hasCustomPauseWindows ? "pencil.circle" : "plus.circle"
          ) {
            impactHaptic.impactOccurred()
            showingPauseEditor = true
          }
        }
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  /// Whether the edited times represent a cross-midnight shift
  private var isCrossMidnightShift: Bool {
    guard let start = editedStartTime, let end = editedEndTime else { return false }
    let startStr = formatTimeToString(start)
    let endStr = formatTimeToString(end)
    return endStr <= startStr && endStr != "00:00"
  }

  // MARK: - Error Banner

  @ViewBuilder
  private func errorBanner(message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
      Spacer()
    }
    .padding(Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexError.opacity(0.1))
    )
  }

  // MARK: - Action Buttons

  private var editOptionsSection: some View {
    VStack(spacing: Spacing.sm) {
      if canEditSupplements {
        inlineEditOptionButton(
          title: String(localized: .supplementsEditButton),
          systemImage: "slider.horizontal.3"
        ) {
          impactHaptic.impactOccurred()
          showingSupplementsEditor = true
        }
      }

      if canEditPauseWindows {
        inlineEditOptionButton(
          title: pauseEditorButtonTitle,
          systemImage: hasCustomPauseWindows ? "pencil.circle" : "plus.circle"
        ) {
          impactHaptic.impactOccurred()
          showingPauseEditor = true
        }
      }
    }
  }

  private func inlineEditOptionButton(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: systemImage)
          .font(.tidexFootnote)
        Text(title)
          .font(.tidexLabel)
      }
      .foregroundColor(.tidexBlue)
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity)
      .background(Color.tidexBlue.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  /// Action buttons for edit mode
  private var editActionButtons: some View {
    VStack(spacing: Spacing.sm) {
      // Save button
      Button {
        saveChanges()
      } label: {
        HStack(spacing: Spacing.xs) {
          if isSaving {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
              .scaleEffect(0.8)
          } else {
            Image(systemName: "checkmark")
              .font(.tidexLabel)
          }
          Text(.commonSaveChanges)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexTextOnBrand)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(hasChanges ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
        .cornerRadius(CornerRadius.lg)
      }
      .disabled(isSaving || !hasChanges)

      // Cancel button
      Button {
        cancelEditing()
      } label: {
        Text(.commonCancel)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexSurfaceSecondary)
          .cornerRadius(CornerRadius.lg)
      }
      .disabled(isSaving)
    }
    .padding(.top, Spacing.xs)
  }

  /// Action buttons for view mode
  @ViewBuilder
  private var viewModeActionButtons: some View {
    VStack(spacing: Spacing.md) {
      EarningsBreakdownCard {
        // Edit button (only show if onUpdate callback is provided)
        if onUpdate != nil {
          DetailSheetActionButton(
            title: String(localized: .shiftsEditButton),
            systemImage: "pencil",
            style: .primary
          ) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              isEditing = true
            }
          }
        }

        // Edit recurring shift button (only for virtual shifts)
        if isVirtualShift, let recurringId = shift.shift.recurring_id, onEditRecurring != nil {
          DetailSheetActionButton(
            title: String(localized: .shiftsEditRecurringButton),
            systemImage: "repeat",
            style: .secondary
          ) {
            dismiss()
            // Small delay to allow sheet to dismiss before opening editor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              onEditRecurring?(recurringId)
            }
          }
        }

        // Delete button
        if let onDelete = onDelete {
          deleteButton(onDelete: onDelete, isVirtual: isVirtualShift)
        }
      }

      if showsCalendarSubscriptionCTA {
        DetailSheetActionButton(
          title: String(localized: "calendar.subscription.detail.cta"),
          systemImage: "calendar.badge.clock",
          style: .primary
        ) {
          showingCalendarSubscriptionConfirmation = true
        }
      }
    }
  }

  private var earningsSection: some View {
    VStack(spacing: Spacing.md) {
      // Section header
      HStack {
        Image(systemName: "creditcard")
          .foregroundColor(.tidexBlue)
        Text(.shiftsEarningsSection)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      // Earnings card
      EarningsBreakdownCard {
        // Base Pay (show when there are supplements or a separate break deduction row)
        if hasEarningsBreakdown {
          earningsRow(
            label: String(localized: .shiftsBasePay),
            value: formatCurrency(displayedBasePay)
          )

          Divider()
        }

        // Supplement breakdown section
        if hasSupplementBreakdown {
          supplementBreakdownSection
        }

        if shouldShowBreakDeductionRow, let breakdown = breakDeductionBreakdown {
          breakDeductionSection(breakdown)

          Divider()
        }

        // Gross
        earningsRow(
          label: String(localized: .shiftsGrossPay),
          value: formatCurrency(shift.grossPay),
          isHighlighted: !showTaxBreakdown && !hasEarningsBreakdown
        )

        if showTaxBreakdown {
          Divider()

          // Tax deduction
          earningsRow(
            label: String(localized: .shiftsTaxDeduction),
            value: "−\(formatCurrency(shift.taxAmount))",
            valueColor: .tidexError
          )

          Divider()

          // Net (highlighted)
          earningsRow(
            label: String(localized: .shiftsNetPay),
            value: formatCurrency(shift.netPay),
            isHighlighted: true
          )
        }

        if canEditSupplements {
          Divider()
          inlineEditOptionButton(
            title: String(localized: .supplementsEditButton),
            systemImage: "slider.horizontal.3"
          ) {
            impactHaptic.impactOccurred()
            showingSupplementsEditor = true
          }
        }
      }
    }
  }

  @ViewBuilder
  private func breakDeductionSection(_ breakdown: BreakDeductionBreakdown) -> some View {
    VStack(spacing: Spacing.xs) {
      let canExpand = breakdown.parts.count > 1

      if canExpand {
        Button {
          impactHaptic.impactOccurred()
          withAnimation(.easeInOut(duration: 0.18)) {
            isBreakDeductionExpanded.toggle()
          }
        } label: {
          breakDeductionTotalRow(breakdown, showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(breakDeductionLabel)
        .accessibilityValue("−\(formatCurrency(breakdown.totalAmount))")
        .accessibilityHint(Text(.shiftsBreakDeductionExpandAccessibilityHint))
      } else {
        breakDeductionTotalRow(breakdown, showsChevron: false)
      }

      if canExpand && isBreakDeductionExpanded {
        VStack(spacing: Spacing.xs) {
          ForEach(breakdown.parts) { part in
            breakDeductionPartView(part)
          }

          Text(breakDeductionExplanation)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.xxxs)
        }
        .padding(.top, Spacing.xxxs)
      }
    }
  }

  private func breakDeductionTotalRow(
    _ breakdown: BreakDeductionBreakdown,
    showsChevron: Bool
  ) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(breakDeductionLabel)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      if showsChevron {
        Image(systemName: "chevron.down")
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
          .rotationEffect(.degrees(isBreakDeductionExpanded ? 180 : 0))
      }

      Spacer()

      Text("−\(formatCurrency(breakdown.totalAmount))")
        .font(.tidexLabel)
        .foregroundColor(.tidexError)
    }
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func breakDeductionPartView(_ part: BreakDeductionPart) -> some View {
    switch part.kind {
    case .base:
      breakDeductionBasePayCard(part)
    case .supplement:
      breakDeductionSupplementCard(part)
    }
  }

  private func breakDeductionBasePayCard(_ part: BreakDeductionPart) -> some View {
    EarningsBreakDeductionDetailCard(
      title: String(localized: .shiftsBreakDeductionPartBasePay),
      amount: "−\(formatCurrency(part.amount))",
      detailTitle: String(localized: .shiftsBreakDeduction),
      detailValue: part.rate.map { "\(formatHoursValue(part.hours)) × \(formatCurrency($0))" }
        ?? formatHoursValue(part.hours)
    )
  }

  @ViewBuilder
  private func breakDeductionSupplementCard(_ part: BreakDeductionPart) -> some View {
    if let segment = part.supplementSegment {
      EarningsBreakDeductionDetailCard(
        title: String(localized: .shiftsBreakDeductionPartSupplement),
        amount: "−\(formatCurrency(part.amount))",
        detailTitle: segmentTimeRange(segment),
        detailValue: "\(formatHoursValue(part.hours)) × \(formatCurrency(segment.rate))",
        forcesLeftToRight: true
      )
    } else {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
        Text(.shiftsBreakDeductionPartSupplement)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)

        Spacer()

        Text("\(formatHoursValue(part.hours)) / −\(formatCurrency(part.amount))")
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
    }
  }

  /// Supplement breakdown showing each time period with supplements
  @ViewBuilder
  private var supplementBreakdownSection: some View {
    VStack(spacing: Spacing.sm) {
      let canExpand = !supplementSegments.isEmpty

      if canExpand {
        Button {
          impactHaptic.impactOccurred()
          withAnimation(.easeInOut(duration: 0.18)) {
            isSupplementBreakdownExpanded.toggle()
          }
        } label: {
          supplementTotalRow(showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.shiftsTotalSupplement))
        .accessibilityValue(formatCurrency(displayedSupplementPay))
      } else {
        supplementTotalRow(showsChevron: false)
      }

      if canExpand && isSupplementBreakdownExpanded {
        ForEach(supplementSegments) { segment in
          supplementSegmentRow(segment)
        }
      }

      Divider()
    }
  }

  private func supplementTotalRow(showsChevron: Bool) -> some View {
    HStack(spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        Text(.shiftsTotalSupplement)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)

        if showsChevron {
          Image(systemName: "chevron.down")
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .rotationEffect(.degrees(isSupplementBreakdownExpanded ? 180 : 0))
        }

        if hasCustomSupplements {
          Text(.shiftsCustomized)
            .font(.tidexMicro)
            .foregroundColor(.tidexBlue)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
              Capsule()
                .fill(Color.tidexBlue.opacity(0.15))
            )
        }
      }

      Spacer()

      Text(formatCurrency(displayedSupplementPay))
        .font(.tidexLabel)
        .foregroundColor(.tidexTextPrimary)
    }
    .contentShape(Rectangle())
  }

  /// A single supplement segment row showing time range, hours × rate, and amount
  @ViewBuilder
  private func supplementSegmentRow(_ segment: SupplementSegment) -> some View {
    EarningsSupplementBreakdownDetailCard(
      timeRange: segmentTimeRange(segment),
      hoursAndRate: "\(formatHoursValue(segment.actualHours)) × \(formatCurrency(segment.rate))",
      amount: formatCurrency(segment.amount)
    )
  }

  /// Format hours value (e.g., "2.50 t")
  private func formatHoursValue(_ hours: Double) -> String {
    return String(format: "%.2f t", hours)
  }

  private func formatPauseWindow(_ window: PauseWindow) -> String {
    "\(window.start) – \(window.end)"
  }

  private func durationMinutes(for window: PauseWindow) -> Int {
    let start = minutes(for: window.start)
    var end = minutes(for: window.end)
    if end <= start {
      end += 24 * 60
    }
    return end - start
  }

  private func minutes(for hhmm: String) -> Int {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return 0 }
    return (parts[0] * 60) + parts[1]
  }

  private func segmentTimeRange(_ segment: SupplementSegment) -> String {
    let range = segment.timeRange
    guard layoutDirection == .rightToLeft else { return range }
    let parts = range.components(separatedBy: " – ")
    if parts.count == 2 {
      return "\(parts[1]) – \(parts[0])"
    }
    return range
  }

  @ViewBuilder
  private func earningsRow(
    label: String,
    value: String,
    isHighlighted: Bool = false,
    valueColor: Color = .tidexTextPrimary
  ) -> some View {
    EarningsBreakdownCard<EmptyView>.Row(
      label: label,
      value: value,
      valueColor: valueColor,
      isHighlighted: isHighlighted
    )
  }

  private var virtualShiftBanner: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "repeat")
        .font(.tidexBody)
        .foregroundColor(.tidexBlue)

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(.shiftsRecurringShift)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)
        Text(.shiftsRecurringShiftDescription)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexBlue.opacity(0.1))
    )
  }

  @ViewBuilder
  private func deleteButton(onDelete: @escaping () -> Void, isVirtual: Bool) -> some View {
    DetailSheetActionButton(
      title: isVirtual
        ? String(localized: .shiftsExcludeButton)
        : String(localized: .shiftsDeleteButton),
      systemImage: isVirtual ? "minus.circle" : "trash",
      style: .destructive
    ) {
      onDelete()
    }
    .padding(.top, Spacing.xs)
  }

  /// Footer showing when the shift was added and, when applicable, last edited.
  @ViewBuilder
  private func shiftTimestampFooter(createdAt: Date?, updatedAt: Date?) -> some View {
    if let createdAt {
      VStack(spacing: Spacing.xxs) {
        Text(String(localized: "shifts.added") + " " + formattedShiftTimestamp(createdAt))

        if let updatedAt, !timestampsMatch(createdAt, updatedAt) {
          Text(String(localized: .shiftsLastEdited) + " " + formattedShiftTimestamp(updatedAt))
        }
      }
      .font(.tidexCaptionRegular)
      .foregroundColor(.tidexTextMuted)
      .frame(maxWidth: .infinity)
      .padding(.top, Spacing.xs)
    } else if let updatedAt {
      Text(String(localized: .shiftsLastEdited) + " " + formattedShiftTimestamp(updatedAt))
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xs)
    }
  }

  private func timestampsMatch(_ lhs: Date, _ rhs: Date) -> Bool {
    abs(lhs.timeIntervalSince(rhs)) < 1
  }

  /// Format shift metadata dates with relative or absolute formatting.
  private func formattedShiftTimestamp(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()

    // If within the last 7 days, use relative formatting
    if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .full
      return formatter.localizedString(for: date, relativeTo: now)
    } else {
      // Otherwise use a short date format
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      return formatter.string(from: date)
    }
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  private var viewerUserId: String? {
    coordinator.getCurrentUserId()
  }

  private var canSendShiftSnapshots: Bool {
    FriendsMessagingCapabilities.shared.canSendShiftSnapshots
  }

  private func makeShiftSnapshotDraft(for recipient: ShareRecipient) throws
    -> ComposerShiftSnapshotDraft
  {
    switch snapshotShareContext {
    case .own:
      guard let viewerUserId else {
        throw FriendsMessagingServiceError.notAuthenticated
      }
      return OwnShiftSnapshotBuilder(
        shift: shift,
        jobName: jobName,
        jobColorHex: jobColorHex,
        currency: currency,
        ownerUserId: viewerUserId,
        ownerDisplayName: coordinator.userDisplayName,
        ownerAvatarUrl: coordinator.userAvatarUrl
      )
      .build(for: recipient)
    case .shared(let owner):
      return SharedShiftSnapshotBuilder(
        shift: shift,
        jobName: jobName,
        jobColorHex: jobColorHex,
        currency: currency,
        owner: owner
      )
      .build()
    }
  }
}

// MARK: - Share Options Sheet

/// Bottom sheet for selecting share options
private struct ShareOptionsSheet: View {
  let onShowEarnings: () -> Void
  let onHideEarnings: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: Spacing.mlg) {
      // Title
      Text(.shiftsShareTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
        .padding(.top, Spacing.md)

      VStack(spacing: Spacing.sm) {
        // Show earnings option
        Button {
          onShowEarnings()
        } label: {
          HStack(spacing: Spacing.msm) {
            Image(systemName: "eye")
              .font(.tidexTitle2)
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(.shiftsShareShowEarnings)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)

        // Hide earnings option
        Button {
          onHideEarnings()
        } label: {
          HStack(spacing: Spacing.msm) {
            Image(systemName: "eye.slash")
              .font(.tidexTitle2)
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(.shiftsShareHideEarnings)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Spacing.mlg)

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }
}

struct ShareDestinationSheet: View {
  let onShareAsImage: () -> Void
  let onShareInChat: () -> Void

  var body: some View {
    VStack(spacing: Spacing.mlg) {
      Text(.shiftsShareTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
        .padding(.top, Spacing.md)

      VStack(spacing: Spacing.sm) {
        Button(action: onShareInChat) {
          HStack(spacing: Spacing.msm) {
            Image(systemName: "bubble.left.and.text.bubble.right")
              .font(.tidexTitle2)
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(LocalizedStringResource("friends.chat.send_to_chat", table: "Localizable"))
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)

        Button(action: onShareAsImage) {
          HStack(spacing: Spacing.msm) {
            Image(systemName: "photo.on.rectangle")
              .font(.tidexTitle2)
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(LocalizedStringResource("shifts.share_as_image", table: "Localizable"))
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Spacing.mlg)

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }
}

// MARK: - Supplement Segment

/// A grouped supplement segment for display
struct SupplementSegment: Identifiable, Equatable {
  let fromMin: Double
  let toMin: Double
  let rate: Double
  let actualHours: Double

  var id: String { "\(fromMin)-\(toMin)-\(rate)" }

  /// Format minutes to display time (e.g., "21:00")
  func formatTime(_ minutes: Double) -> String {
    let dayOffset = Int(minutes / 1440)
    let remainder = Int(minutes) % 1440
    let normalizedMinutes = remainder < 0 ? remainder + 1440 : remainder
    let isFullDay = normalizedMinutes == 0 && Int(minutes) != 0
    let hours = isFullDay ? 24 : normalizedMinutes / 60
    let mins = isFullDay ? 0 : normalizedMinutes % 60
    let base = String(format: "%02d:%02d", hours, mins)
    if dayOffset > 0 {
      return "\(base) (+\(dayOffset))"
    } else if dayOffset < 0 {
      return "\(base) (\(dayOffset))"
    }
    return base
  }

  /// Formatted time range string
  var timeRange: String {
    let from = formatTime(fromMin)
    let to = formatTime(toMin)
    // Replace 23:59 with 24:00 for cleaner display
    let toDisplay = to == "23:59" ? "24:00" : to
    return "\(from) – \(toDisplay)"
  }

  /// Total supplement amount for this segment
  var amount: Double {
    actualHours * rate
  }
}

struct BreakDeductionBreakdown: Equatable {
  let parts: [BreakDeductionPart]

  var totalAmount: Double {
    parts.reduce(0) { $0 + $1.amount }
  }

  static func basePay(for periods: [WagePeriod]) -> Double {
    roundedCurrency(
      periods.reduce(0) {
        $0 + payFor(hours: max(0, $1.durationHours), rate: $1.baseRate)
      })
  }

  static func supplementPay(for periods: [WagePeriod]) -> Double {
    roundedCurrency(
      periods.reduce(0) {
        $0 + payFor(hours: max(0, $1.durationHours), rate: $1.supplementRate)
      })
  }

  static func make(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod]
  ) -> BreakDeductionBreakdown? {
    var parts: [BreakDeductionPart] = []

    let baseAmount = roundedCurrency(
      payDelta(
        originalPeriods: originalPeriods,
        adjustedPeriods: adjustedPeriods,
        pay: { payFor(hours: max(0, $0.durationHours), rate: $0.baseRate) }
      ))
    let baseHours = deductedBaseHours(
      originalPeriods: originalPeriods,
      adjustedPeriods: adjustedPeriods
    )

    if isDisplayable(baseAmount) {
      parts.append(
        BreakDeductionPart(
          id: "base",
          kind: .base,
          supplementSegment: nil,
          hours: baseHours,
          rate: baseHours > 0 ? baseAmount / baseHours : nil,
          amount: baseAmount
        ))
    }

    parts.append(
      contentsOf: supplementParts(
        originalPeriods: originalPeriods,
        adjustedPeriods: adjustedPeriods
      ))

    guard !parts.isEmpty else { return nil }
    return BreakDeductionBreakdown(parts: parts)
  }

  private static func supplementParts(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod]
  ) -> [BreakDeductionPart] {
    var parts: [BreakDeductionPart] = []
    var i = 0

    while i < originalPeriods.count {
      let period = originalPeriods[i]
      guard period.supplementRate > 0 else {
        i += 1
        continue
      }

      let groupStart = period.fromMin
      var groupEnd = period.toMin
      let rate = period.supplementRate
      var j = i + 1

      while j < originalPeriods.count && originalPeriods[j].supplementRate == rate {
        groupEnd = originalPeriods[j].toMin
        j += 1
      }

      let originalMetrics = overlappingMetrics(
        periods: originalPeriods,
        from: groupStart,
        to: groupEnd,
        supplementRate: rate
      )
      let adjustedMetrics = overlappingMetrics(
        periods: adjustedPeriods,
        from: groupStart,
        to: groupEnd,
        supplementRate: rate
      )
      let deductedHours = max(0, originalMetrics.hours - adjustedMetrics.hours)
      let amount = roundedCurrency(max(0, originalMetrics.pay - adjustedMetrics.pay))

      if isDisplayable(amount) {
        parts.append(
          BreakDeductionPart(
            id: "supplement-\(groupStart)-\(groupEnd)-\(rate)",
            kind: .supplement,
            supplementSegment: SupplementSegment(
              fromMin: groupStart,
              toMin: groupEnd,
              rate: rate,
              actualHours: deductedHours
            ),
            hours: deductedHours,
            rate: rate,
            amount: amount
          ))
      }

      i = j
    }

    return parts
  }

  private static func overlappingMetrics(
    periods: [WagePeriod],
    from: Double,
    to: Double,
    supplementRate: Double
  ) -> (hours: Double, pay: Double) {
    periods
      .filter { $0.supplementRate == supplementRate }
      .reduce((hours: 0, pay: 0)) { total, current in
        let overlapStart = max(current.fromMin, from)
        let overlapEnd = min(current.toMin, to)
        guard overlapEnd > overlapStart else { return total }
        let hours = (overlapEnd - overlapStart) / 60.0
        return (
          hours: total.hours + hours,
          pay: total.pay + payFor(hours: hours, rate: supplementRate)
        )
      }
  }

  private static func deductedBaseHours(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod]
  ) -> Double {
    let originalHours = originalPeriods.reduce(0) { $0 + max(0, $1.durationHours) }
    let adjustedHours = adjustedPeriods.reduce(0) { $0 + max(0, $1.durationHours) }
    return max(0, originalHours - adjustedHours)
  }

  private static func payDelta(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod],
    pay: (WagePeriod) -> Double
  ) -> Double {
    let originalPay = originalPeriods.reduce(0) { $0 + pay($1) }
    let adjustedPay = adjustedPeriods.reduce(0) { $0 + pay($1) }
    return max(0, originalPay - adjustedPay)
  }

  private static func roundedCurrency(_ amount: Double) -> Double {
    (amount * 100).rounded() / 100
  }

  private static func payFor(hours: Double, rate: Double) -> Double {
    let roundedHours = (hours * 1000).rounded() / 1000
    return roundedCurrency(roundedHours * rate)
  }

  private static func isDisplayable(_ amount: Double) -> Bool {
    roundedCurrency(amount) > 0
  }
}

struct BreakDeductionPart: Identifiable, Equatable {
  enum Kind: Equatable {
    case base
    case supplement
  }

  let id: String
  let kind: Kind
  let supplementSegment: SupplementSegment?
  let hours: Double
  let rate: Double?
  let amount: Double
}

// MARK: - Preview

#Preview("With Supplements") {
  // Evening shift with supplements (17:00-23:00)
  // Supplement applies from 21:00-24:00 at 45 kr/hour
  let eveningSupplementPeriods = [
    // 17:00-21:00: 4 hours base only (1020 min to 1260 min)
    WagePeriod(fromMin: 1020, toMin: 1260, baseRate: 200, supplementRate: 0),
    // 21:00-23:00: 2 hours with supplement (1260 min to 1380 min)
    WagePeriod(fromMin: 1260, toMin: 1380, baseRate: 200, supplementRate: 45),
  ]

  return ShiftDetailsSheet(
    shift: ShiftWithComputations(
      shift: ShiftRow(
        id: "preview-1",
        user_id: "user-1",
        shift_date: "2025-01-17",
        start_time: "17:00",
        end_time: "23:00",
        custom_supplements: nil,
        updated_at: Date().addingTimeInterval(-3600)  // 1 hour ago
      ),
      computed: ShiftComputed(
        id: "preview-1",
        durationHours: 6.0,
        paidHours: 5.5,
        basePay: 1100,  // 5.5h × 200 kr
        supplementPay: 90,  // 2h × 45 kr
        gross: 1190,
        wagePeriods: eveningSupplementPeriods,
        originalWagePeriods: eveningSupplementPeriods,
        breakAudit: BreakAudit(
          method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
      ),
      taxEnabled: true,
      taxPercentage: 30
    ),
    onDelete: { print("Delete tapped") },
    onUpdate: { result in print("Update: \(result)") }
  )
}

#Preview("Edit Mode") {
  ShiftDetailsSheet(
    shift: ShiftWithComputations(
      shift: ShiftRow(
        id: "preview-edit",
        user_id: "user-1",
        shift_date: "2025-01-17",
        start_time: "08:00",
        end_time: "16:00",
        custom_supplements: nil
      ),
      computed: ShiftComputed(
        id: "preview-edit",
        durationHours: 8.0,
        paidHours: 7.5,
        basePay: 1500,
        supplementPay: 0,
        gross: 1500,
        wagePeriods: [
          WagePeriod(fromMin: 480, toMin: 960, baseRate: 200, supplementRate: 0)
        ],
        originalWagePeriods: [
          WagePeriod(fromMin: 480, toMin: 960, baseRate: 200, supplementRate: 0)
        ],
        breakAudit: BreakAudit(
          method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
      ),
      taxEnabled: false,
      taxPercentage: 0
    ),
    onDelete: { print("Delete tapped") },
    onUpdate: { result in print("Update: \(result)") },
    startInEditMode: true
  )
}

#Preview("No Supplements") {
  ShiftDetailsSheet(
    shift: ShiftWithComputations(
      shift: ShiftRow(
        id: "preview-2",
        user_id: "user-1",
        shift_date: "2025-01-17",
        start_time: "08:00",
        end_time: "16:00",
        custom_supplements: nil
      ),
      computed: ShiftComputed(
        id: "preview-2",
        durationHours: 8.0,
        paidHours: 7.5,
        basePay: 1500,
        supplementPay: 0,
        gross: 1500,
        wagePeriods: [
          WagePeriod(fromMin: 480, toMin: 960, baseRate: 200, supplementRate: 0)
        ],
        originalWagePeriods: [
          WagePeriod(fromMin: 480, toMin: 960, baseRate: 200, supplementRate: 0)
        ],
        breakAudit: BreakAudit(
          method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
      ),
      taxEnabled: false,
      taxPercentage: 0
    ),
    onDelete: { print("Delete tapped") },
    onUpdate: { result in print("Update: \(result)") }
  )
}
