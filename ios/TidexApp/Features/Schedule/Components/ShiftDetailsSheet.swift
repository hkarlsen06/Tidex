import AppIntents
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
  case recurringOccurrence(recurringId: String, date: String)
  case standalone(shiftId: String)
}

struct ShiftPauseEditResult: Equatable {
  let target: ShiftPauseEditTarget
  let customPauseWindows: CustomPauseWindows?
}

struct ShiftDetailsPresentationPolicy: Equatable {
  let snapshotShareContext: ShiftSnapshotShareContext

  var showsEarningsDetails: Bool {
    switch snapshotShareContext {
    case .own:
      return true

    case .shared(let owner):
      return owner.showEarnings
    }
  }
}

struct ShiftDetailsSheet: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  private let initialShift: ShiftWithComputations
  @State private var recalculatedShift: ShiftWithComputations?
  @State private var recalculatedTariffRules: [SupplementRule]?
  @State var showingPaySettings = false

  var shift: ShiftWithComputations { recalculatedShift ?? initialShift }
  /// Job name to display in the header badge (only set when user has multiple jobs)
  let jobName: String?
  /// Job color hex for the badge (e.g. "#3B82F6")
  let jobColorHex: String?
  let onDelete: (() -> Void)?
  let onUpdate: ((ShiftEditResult) async throws -> Void)?
  let onUpdatePause: ((ShiftPauseEditResult) -> Void)?
  let onEditRecurring: ((String) -> Void)?  // Callback with recurring shift ID
  let onStopRecurringAfterDate: ((String, String) async throws -> Void)?
  let showsCalendarSubscriptionCTA: Bool
  let onShowInCalendarRequested: (() -> Void)?
  var onSendToChatCompleted: ((SendShiftToChatResult) -> Void)?
  let snapshotShareContext: ShiftSnapshotShareContext
  /// Tariff supplement rules from the applicable snapshot (used for supplements editor)
  private let initialTariffRules: [SupplementRule]
  private var tariffRules: [SupplementRule] { recalculatedTariffRules ?? initialTariffRules }

  @Environment(AppCoordinator.self) var coordinator
  @Environment(\.userCurrency) var currency
  @Environment(\.layoutDirection) var layoutDirection
  @Environment(\.dismiss) var dismiss
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  // MARK: - Edit Mode State

  /// Whether the sheet is in edit mode
  @State var isEditing = false

  /// Whether to start in edit mode (passed from parent)
  var startInEditMode: Bool = false

  /// Edited date (ISO format YYYY-MM-DD)
  @State var editedDate = Date()  // swiftlint:disable:this explicit_type_interface

  /// Edited start time
  @State var editedStartTime: Date?

  /// Edited end time
  @State var editedEndTime: Date?

  /// Which time input field is focused (for TimeRangePicker)
  @State var focusedTimeField: TimeInputField?

  /// Whether the note editor is focused
  @FocusState var isNoteFieldFocused: Bool

  private enum SupplementsEdit {
    case unchanged
    /// Nil keeps the tariff's supplements. An empty rule list means none.
    case changed(CustomSupplementsData?)

    var isChanged: Bool {
      if case .changed = self { return true }
      return false
    }

    /// What `ShiftEditResult.customSupplements` sends. Nil leaves the supplements as they are.
    var saved: CustomSupplementsData? {
      if case .changed(let supplements) = self { return supplements }
      return nil
    }
  }

  /// Supplements chosen in edit mode, saved when the user taps Save.
  @State private var supplementsEdit = SupplementsEdit.unchanged

  /// Edited note text
  @State private var editedNote = ""

  /// Whether note was edited (to support explicit clear)
  @State private var noteWasEdited = false

  /// Optimistic note value used when a note-only save keeps the sheet open
  @State private var optimisticNoteOverride: String?

  /// Whether the optimistic note override should be used
  @State private var hasOptimisticNoteOverride = false

  /// Whether currently saving
  @State var isSaving = false

  /// Error message to display
  @State private var errorMessage: String?

  /// Whether showing the supplements editor sheet
  @State var showingSupplementsEditor = false

  /// Whether showing the pause editor sheet
  @State var showingPauseEditor = false

  /// Whether the break deduction breakdown is expanded
  @State var isBreakDeductionExpanded = false

  /// Whether the supplement breakdown is expanded
  @State var isSupplementBreakdownExpanded = false

  /// Whether the overtime breakdown is expanded
  @State var isOvertimeBreakdownExpanded = false

  /// Whether showing the share destination picker
  @State private var showingShareDestinationPicker = false

  /// Whether showing the image share options dialog
  @State private var showingImageShareOptions = false

  /// Whether showing the send-to-chat recipient picker
  @State private var showingSendToChatSheet = false
  @State var showingCalendarSubscriptionConfirmation = false
  @State var showingStopRecurringConfirmation = false
  @State var isStoppingRecurringAfterDate = false

  /// Haptic feedback generator
  let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

  // MARK: - Computed Properties

  var isVirtualShift: Bool {
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
    onStopRecurringAfterDate: ((String, String) async throws -> Void)? = nil,
    showsCalendarSubscriptionCTA: Bool = false,
    onShowInCalendarRequested: (() -> Void)? = nil,
    onSendToChatCompleted: ((SendShiftToChatResult) -> Void)? = nil,
    snapshotShareContext: ShiftSnapshotShareContext = .own,
    startInEditMode: Bool = false,
    tariffRules: [SupplementRule] = []
  ) {
    self.initialShift = shift
    self.jobName = jobName
    self.jobColorHex = jobColorHex
    self.onDelete = onDelete
    self.onUpdate = onUpdate
    self.onUpdatePause = onUpdatePause
    self.onEditRecurring = onEditRecurring
    self.onStopRecurringAfterDate = onStopRecurringAfterDate
    self.showsCalendarSubscriptionCTA = showsCalendarSubscriptionCTA
    self.onShowInCalendarRequested = onShowInCalendarRequested
    self.onSendToChatCompleted = onSendToChatCompleted
    self.snapshotShareContext = snapshotShareContext
    self.startInEditMode = startInEditMode
    self.initialTariffRules = tariffRules
  }

  var formattedDate: String {
    guard let date = Date.fromISODateString(shift.shiftDate) else {
      return shift.shiftDate
    }

    return date.formatted(
      .dateTime.weekday(.wide).day().month(.wide).year().locale(.appLocale)
    ).sentenceCased()
  }

  private var formattedStopRecurringDate: String {
    guard let date = Date.fromISODateString(shift.shiftDate) else {
      return shift.shiftDate
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.appLocale
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  var formattedTimeRange: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  var formattedHours: String {
    let hoursLabel = String(localized: .commonHours)
    let hoursValue = shift.paidHours.formatted(
      .number.precision(.fractionLength(2)).locale(.appLocale))
    return "\(hoursValue) \(hoursLabel)"
  }

  var showTaxBreakdown: Bool {
    shift.taxEnabled && shift.taxAmount > 0
  }

  private var presentationPolicy: ShiftDetailsPresentationPolicy {
    ShiftDetailsPresentationPolicy(snapshotShareContext: snapshotShareContext)
  }

  var showsEarningsDetails: Bool {
    presentationPolicy.showsEarningsDetails
  }

  /// Whether this shift has supplement pay to show breakdown
  var hasSupplementBreakdown: Bool {
    displayedSupplementPay > 0 && !supplementSegments.isEmpty
  }

  var hasOvertimeBreakdown: Bool {
    displayedOvertimePay > 0 && !overtimeSegments.isEmpty
  }

  var hasEarningsBreakdown: Bool {
    hasSupplementBreakdown || hasOvertimeBreakdown || shouldShowBreakDeductionRow
  }

  var displayedBasePay: Double {
    shouldShowBreakDeductionRow
      ? BreakDeductionBreakdown.basePay(for: shift.computed.preBreakWagePeriods)
      : shift.computed.basePay
  }

  var displayedSupplementPay: Double {
    return roundedCurrency(max(0, displayedTotalSupplementPay - displayedOvertimePay))
  }

  private var displayedTotalSupplementPay: Double {
    shouldShowBreakDeductionRow
      ? BreakDeductionBreakdown.supplementPay(for: shift.computed.preBreakWagePeriods)
      : shift.computed.supplementPay
  }

  var displayedOvertimePay: Double {
    PayrollCalculator.payTotals(
      for: shift.computed.classifiedWagePeriods.filter { $0.isOvertime == true }
    ).supplement
  }

  /// Check if shift has custom supplements (including explicitly empty rules)
  var hasCustomSupplements: Bool {
    return shift.shift.custom_supplements != nil
  }

  var noteBinding: Binding<String> {
    Binding(
      get: { editedNote },
      set: { note in
        editedNote = note
        noteWasEdited = true
      }
    )
  }

  var displayedNote: String? {
    hasOptimisticNoteOverride ? optimisticNoteOverride : shift.note
  }

  private var normalizedCustomPauseWindows: CustomPauseWindows? {
    PauseWindowSupport.normalize(shift.shift.custom_pause_windows)
  }

  var hasCustomPauseWindows: Bool {
    normalizedCustomPauseWindows != nil
  }

  var shouldShowBreakSection: Bool {
    showsEarningsDetails
      && (onUpdatePause != nil || hasCustomPauseWindows
        || shift.computed.breakAudit.deductedHours > 0)
  }

  private var shouldShowEditOptionsSection: Bool {
    canEditSupplements || canEditPauseWindows
  }

  /// Net pay when tax is deducted, otherwise gross. The breakdown card adds up to this.
  var headlinePay: Double {
    showTaxBreakdown ? shift.netPay : shift.grossPay
  }

  var headlinePayLabel: LocalizedStringResource {
    showTaxBreakdown ? .shiftsNetPay : .shiftsGrossPay
  }

  var showsPayBreakdownCard: Bool {
    hasEarningsBreakdown || showTaxBreakdown
  }

  var canManageRecurring: Bool {
    isVirtualShift && shift.shift.recurring_id != nil && onEditRecurring != nil
  }

  var canStopRecurring: Bool {
    isVirtualShift && shift.shift.recurring_id != nil && onStopRecurringAfterDate != nil
  }

  var canEditSupplements: Bool {
    onUpdate != nil && !tariffRules.isEmpty
  }

  var canEditPauseWindows: Bool {
    onUpdatePause != nil
  }

  var displayedPauseWindows: [PauseWindow] {
    if shift.computed.breakAudit.source == .customPauseWindows,
      let appliedPauseWindows = shift.computed.breakAudit.appliedPauseWindows,
      !appliedPauseWindows.isEmpty
    {
      return appliedPauseWindows
    }

    return normalizedCustomPauseWindows?.windows ?? []
  }

  var deductedPauseMinutes: Int {
    Int((shift.computed.breakAudit.deductedHours * 60).rounded())
  }

  var breakDeductionBreakdown: BreakDeductionBreakdown? {
    BreakDeductionBreakdown.make(
      originalPeriods: shift.computed.preBreakWagePeriods,
      adjustedPeriods: shift.computed.wagePeriods
    )
  }

  var shouldShowBreakDeductionRow: Bool {
    shift.computed.breakAudit.deductedHours > 0 && breakDeductionBreakdown != nil
  }

  var breakDeductionLabel: String {
    String(localized: .shiftsBreakDeduction)
  }

  var breakDeductionExplanation: LocalizedStringResource {
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

  var pauseEditorButtonTitle: String {
    hasCustomPauseWindows
      ? String(localized: .shiftsPauseSectionEditWindows)
      : String(localized: .shiftsPauseSectionAddExactWindows)
  }

  private func pauseEditTarget() -> ShiftPauseEditTarget? {
    if let recurringId = shift.shift.recurring_id {
      return .recurringOccurrence(recurringId: recurringId, date: shift.shiftDate)
    }
    return .standalone(shiftId: shift.id)
  }

  /// Base wage rate per hour (for showing in supplement rows)
  private var baseWageRate: Double {
    guard shift.computed.paidHours > 0 else {
      return 0
    }
    return shift.computed.basePay / shift.computed.paidHours
  }

  var supplementSegments: [SupplementSegment] {
    let periods =
      shouldShowBreakDeductionRow
      ? shift.computed.preBreakWagePeriods : shift.computed.classifiedWagePeriods
    return SupplementSegment.grouped(from: periods.filter { $0.isOvertime != true })
  }

  var overtimeSegments: [SupplementSegment] {
    SupplementSegment.grouped(
      from: shift.computed.classifiedWagePeriods.filter { $0.isOvertime == true }
    )
  }

  func roundedCurrency(_ amount: Double) -> Double {
    (amount * 100).rounded() / 100
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      scrollContent
        .background(Color.tidexBackground)
        .navigationTitle(
          isEditing
            ? String(localized: .shiftsEditTitle)
            : String(localized: .shiftsDetailsTitle)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }
    // Lets Siri act on the shift on screen.
    .userActivity(ShiftEntity.viewActivityType) { activity in
      activity.isEligibleForHandoff = false
      activity.appEntityIdentifier = EntityIdentifier(for: ShiftEntity.self, identifier: shift.id)
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
    .interactiveDismissDisabled(
      isEditing && (hasChanges || editedStartTime == nil || editedEndTime == nil)
    )
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
      .presentationDetents([.height(250), .large])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingImageShareOptions) {
      ShareOptionsSheet(
        earningsImage: renderShiftImage(includeEarnings: true),
        hiddenEarningsImage: renderShiftImage(includeEarnings: false)
      )
      .presentationDetents([.height(260), .large])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingSupplementsEditor) {
      CustomSupplementsEditorSheet(
        shift: shift,
        currency: currency,
        tariffRules: tariffRules,
        onSave: { customSupplements in
          showingSupplementsEditor = false
          if isEditing {
            // Saved with the other edits when the user taps Save.
            supplementsEdit = .changed(customSupplements)
          } else {
            saveSupplements(customSupplements)
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
          guard let target = pauseEditTarget() else {
            return
          }
          onUpdatePause?(
            ShiftPauseEditResult(target: target, customPauseWindows: customPauseWindows)
          )
          dismiss()
        },
        onCancel: {
          showingPauseEditor = false
        }
      )
    }
    .sheet(
      isPresented: $showingPaySettings,
      onDismiss: {
        Task { await refreshCalculation() }
      }
    ) {
      if let date = Date.fromISODateString(shift.shiftDate) {
        PaySettingsSheet(
          jobId: shift.shift.job_id, workDate: date, initiallyExpandPayReview: true)
      }
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
      String(localized: .calendarSubscriptionDetailConfirmationTitle),
      isPresented: $showingCalendarSubscriptionConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .commonContinue)) {
        onShowInCalendarRequested?()
      }
      Button(String(localized: .commonCancel), role: .cancel) {
        // The confirmation dialog handles cancellation.
      }
    } message: {
      Text(.calendarSubscriptionDetailConfirmationMessage)
    }
    .confirmationDialog(
      String(localized: .shiftsRecurringStopAfterDateConfirmTitle),
      isPresented: $showingStopRecurringConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .shiftsRecurringStopAfterDateButton), role: .destructive) {
        stopRecurringAfterCurrentDate()
      }
      Button(String(localized: .commonCancel), role: .cancel) {
        // The confirmation dialog handles cancellation.
      }
    } message: {
      Text(
        String(
          localized: .shiftsRecurringStopAfterDateConfirmMessage(formattedStopRecurringDate)
        )
      )
    }
  }

  private var scrollContent: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        if isEditing {
          editModeSections
        } else {
          headerSection
        }

        if let error = errorMessage {
          errorBanner(message: error)
        }

        if !isEditing {
          viewModeSections
        }
      }
      .padding(Spacing.mlg)
      .adaptiveContentWidth()
    }
  }

  @ViewBuilder
  private var editModeSections: some View {
    editableTimeSection

    noteEditorSection

    if shouldShowEditOptionsSection {
      editOptionsSection
    }
  }

  @ViewBuilder
  private var shareAndDeleteButtons: some View {
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
        .foregroundStyle(Color.tidexTextPrimary)
        .accessibilityLabel(Text(.shiftsShareTitle))
    }

    if let onDelete {
      Button(role: .destructive) {
        onDelete()
      } label: {
        Image(systemName: isVirtualShift ? "minus.circle" : "trash")
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexError)
      }
      .accessibilityLabel(
        Text(
          isVirtualShift
            ? String(localized: .shiftsExcludeButton)
            : String(localized: .shiftsDeleteButton)
        )
      )
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarLeading) {
      if isEditing {
        Button(String(localized: .commonCancel)) {
          cancelEditing()
        }
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextSecondary)
      } else {
        shareAndDeleteButtons
      }
    }
    ToolbarItem(placement: .topBarTrailing) {
      if isEditing {
        Button(String(localized: .commonSave)) {
          saveChanges()
        }
        .font(.tidexButton)
        .foregroundStyle(Color.tidexBlueText)
        .disabled(isSaving || !hasChanges)
        .opacity(isSaving || !hasChanges ? 0.5 : 1)
      } else {
        Button(String(localized: .commonDone)) {
          dismiss()
        }
        .font(.tidexButton)
        .foregroundStyle(Color.tidexBlueText)
      }
    }
  }

  // MARK: - Edit State Management

  private func refreshCalculation() async {
    guard snapshotShareContext == .own,
      let userId = AuthSessionManager.shared.offlineUserIdFallback(),
      shift.shift.user_id == userId,
      let date = Date.fromISODateString(shift.shiftDate)
    else { return }
    let reader = MonthlyPayrollReadService.shared
    reader.invalidateSharedCache(for: userId)
    let context = await reader.loadContextUsingStoreActor(for: userId, jobId: shift.shift.job_id)
    let month = date.yearMonth()
    let rows = await reader.loadShiftRows(
      for: userId, year: month.year, month: month.month, jobId: shift.shift.job_id
    )
    let results = PayrollEngine.computeShiftsForMonth(
      .init(
        year: month.year, month: month.month, shifts: rows, recurring: context.recurringShifts,
        snapshots: context.snapshots, settings: context.settings, jobs: context.jobs
      ))
    if let updated = results.first(where: { $0.id == shift.id }) {
      recalculatedTariffRules =
        context.snapshots.first {
          $0.id == updated.calculationContext?.wageSnapshotId
        }?.supplements.rules ?? []
      recalculatedShift = updated
    } else {
      errorMessage = String(localized: .settingsPayErrorLoadFailed)
    }
  }

  /// Initialize edit state from the shift data
  private func initializeEditState() {
    supplementsEdit = .unchanged

    // Parse shift date
    if let date = Date.fromISODateString(shift.shiftDate) {
      editedDate = date
    }

    // Parse start time
    if let startTime = ShiftTimeFieldFormat.pickerDate(from: shift.startTime) {
      editedStartTime = startTime
    }

    // Parse end time
    if let endTime = ShiftTimeFieldFormat.pickerDate(from: shift.endTime) {
      editedEndTime = endTime
    }

    editedNote = displayedNote ?? ""
    noteWasEdited = false
  }

  /// Format Date to HH:mm string
  func formatTimeToString(_ date: Date) -> String {
    date.toHourMinuteString()
  }

  /// Check if any changes have been made
  private var hasChanges: Bool {
    guard let start = editedStartTime, let end = editedEndTime else {
      return false
    }
    let newDate = editedDate.toISODateString()
    let newStartTime = ShiftTimeFieldFormat.storedTime(from: start, original: shift.startTime)
    let newEndTime = ShiftTimeFieldFormat.storedTime(from: end, original: shift.endTime)

    return newDate != shift.shiftDate || newStartTime != String(shift.startTime.prefix(5))
      || newEndTime != String(shift.endTime.prefix(5)) || supplementsEdit.isChanged || noteWasEdited
  }

  private var trimmedEditedNote: String? {
    ShiftNoteSupport.normalize(editedNote)
  }

  /// Cancel editing and reset state
  private func cancelEditing() {
    initializeEditState()
    errorMessage = nil
    isNoteFieldFocused = false
    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
      isEditing = false
    }
  }

  func beginNoteEditing() {
    editedNote = displayedNote ?? ""
    noteWasEdited = false
    errorMessage = nil
    focusedTimeField = nil

    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
      isEditing = true
    }

    DispatchQueue.main.async {
      isNoteFieldFocused = true
    }
  }

  /// Render the shift card as a PNG for `ShareOptionsSheet`'s `ShareLink` buttons
  @MainActor
  private func renderShiftImage(includeEarnings: Bool) -> UIImage? {
    ShareableShiftCard(
      shift: shift,
      currency: currency,
      includeEarnings: includeEarnings
    )
    .renderAsImage()
  }

  /// Save changes
  private func saveChanges() {
    guard !isSaving else {
      return
    }
    guard let startTime = editedStartTime, let endTime = editedEndTime else {
      return
    }
    // Validate times (basic validation)
    let newDate = editedDate.toISODateString()
    let newStartTime = ShiftTimeFieldFormat.storedTime(from: startTime, original: shift.startTime)
    let newEndTime = ShiftTimeFieldFormat.storedTime(from: endTime, original: shift.endTime)

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
      && !supplementsEdit.isChanged
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
      customSupplements: supplementsEdit.saved
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
          withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
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

  /// Outside edit mode a supplements change saves at once. It leaves no draft behind, so a
  /// failed save is not sent again with a later note edit.
  private func saveSupplements(_ customSupplements: CustomSupplementsData?) {
    guard !isSaving else { return }
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
    errorMessage = nil
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

  private func stopRecurringAfterCurrentDate() {
    guard !isStoppingRecurringAfterDate else {
      return
    }
    guard let recurringId = shift.shift.recurring_id, let onStopRecurringAfterDate else {
      errorMessage = ShiftSaveError.missingRecurringInfo.localizedDescription
      return
    }

    errorMessage = nil
    isStoppingRecurringAfterDate = true
    impactHaptic.impactOccurred()

    Task {
      do {
        try await onStopRecurringAfterDate(recurringId, shift.shiftDate)
        dismiss()
      } catch {
        errorMessage = ErrorTranslations.translate(error)
      }

      isStoppingRecurringAfterDate = false
    }
  }
}

// MARK: - Preview

#Preview("With Supplements") {
  // Evening shift with supplements (17:00-23:00)
  // Supplement applies from 21:00-24:00 at 45 kr/hour
  let eveningSupplementPeriods = [
    // 17:00-21:00: 4 hours base only (1020 min to 1260 min)
    WagePeriod(fromMin: 1_020, toMin: 1_260, baseRate: 200, supplementRate: 0),
    // 21:00-23:00: 2 hours with supplement (1260 min to 1380 min)
    WagePeriod(fromMin: 1_260, toMin: 1_380, baseRate: 200, supplementRate: 45),
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
        updated_at: Date().addingTimeInterval(-3_600)  // 1 hour ago
      ),
      computed: ShiftComputed(
        id: "preview-1",
        durationHours: 6.0,
        paidHours: 5.5,
        basePay: 1_100,  // 5.5h × 200 kr
        supplementPay: 90,  // 2h × 45 kr
        gross: 1_190,
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
        basePay: 1_500,
        supplementPay: 0,
        gross: 1_500,
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
        basePay: 1_500,
        supplementPay: 0,
        gross: 1_500,
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
