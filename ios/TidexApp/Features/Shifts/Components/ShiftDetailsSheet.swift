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
  /// Custom supplements for this shift. nil = no change, empty rules = clear supplements
  let customSupplements: CustomSupplementsData?
}

struct ShiftDetailsSheet: View {
  let shift: ShiftWithComputations
  let onDelete: (() -> Void)?
  let onUpdate: ((ShiftEditResult) -> Void)?
  let onEditRecurring: ((String) -> Void)?  // Callback with recurring shift ID
  /// Tariff supplement rules from the applicable snapshot (used for supplements editor)
  let tariffRules: [SupplementRule]

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
  @State private var editedStartTime: Date = Date()

  /// Edited end time
  @State private var editedEndTime: Date = Date()

  /// Edited custom supplements (nil = unchanged, set to clear or modify)
  @State private var editedSupplements: CustomSupplementsData?

  /// Whether supplements were edited (to track changes)
  @State private var supplementsWereEdited = false

  /// Whether currently saving
  @State private var isSaving = false

  /// Error message to display
  @State private var errorMessage: String?

  /// Whether showing the supplements editor sheet
  @State private var showingSupplementsEditor = false

  /// Whether showing the share options dialog
  @State private var showingShareOptions = false

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
    onDelete: (() -> Void)? = nil,
    onUpdate: ((ShiftEditResult) -> Void)? = nil,
    onEditRecurring: ((String) -> Void)? = nil,
    startInEditMode: Bool = false,
    tariffRules: [SupplementRule] = []
  ) {
    self.shift = shift
    self.onDelete = onDelete
    self.onUpdate = onUpdate
    self.onEditRecurring = onEditRecurring
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
    return formatter.string(from: date).capitalized
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
    shift.computed.supplementPay > 0 && !supplementSegments.isEmpty
  }

  /// Check if shift has custom supplements
  private var hasCustomSupplements: Bool {
    if let custom = shift.shift.custom_supplements,
      !custom.rules.isEmpty
    {
      return true
    }
    return false
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
    let adjusted = shift.computed.wagePeriods

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
        VStack(spacing: 24) {
          // Header with date
          headerSection

          // Time and hours (editable in edit mode)
          if isEditing {
            editableTimeSection
          } else {
            timeSection
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

          // Last edited timestamp (only in view mode, for non-virtual shifts)
          if !isEditing, let updatedAt = shift.updatedAt, !isVirtualShift {
            lastEditedFooter(date: updatedAt)
          }
        }
        .padding(20)
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
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.tidexTextSecondary)
          } else {
            Button {
              impactHaptic.impactOccurred()
              showingShareOptions = true
            } label: {
              Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tidexBlue)
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if isEditing {
            Button(String(localized: .commonSave)) {
              saveChanges()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.tidexBlue)
            .disabled(isSaving || !hasChanges)
            .opacity(isSaving || !hasChanges ? 0.5 : 1)
          } else {
            Button(String(localized: .commonDone)) {
              dismiss()
            }
            .font(.system(size: 16, weight: .semibold))
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
    .interactiveDismissDisabled(isEditing && hasChanges)
    .sheet(
      isPresented: $showingShareOptions,
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
          showingShareOptions = false
        },
        onHideEarnings: {
          // Prepare the image first, then dismiss - share sheet shows on dismiss
          prepareShiftImage(includeEarnings: false)
          showingShareOptions = false
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
            let editResult = ShiftEditResult(
              shiftId: shift.id,
              shiftDate: shift.shiftDate,
              startTime: shift.startTime,
              endTime: shift.endTime,
              isVirtualShiftConversion: isVirtualShift,
              recurringId: shift.shift.recurring_id,
              originalDate: shift.shiftDate,
              customSupplements: customSupplements
            )
            onUpdate?(editResult)
            dismiss()
          }
        },
        onCancel: {
          showingSupplementsEditor = false
        }
      )
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
    let newDate = formatDateToISO(editedDate)
    let newStartTime = formatTimeToString(editedStartTime)
    let newEndTime = formatTimeToString(editedEndTime)

    return newDate != shift.shiftDate || newStartTime != String(shift.startTime.prefix(5))
      || newEndTime != String(shift.endTime.prefix(5)) || supplementsWereEdited
  }

  /// Cancel editing and reset state
  private func cancelEditing() {
    initializeEditState()
    errorMessage = nil
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      isEditing = false
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
    // Validate times (basic validation)
    let newDate = formatDateToISO(editedDate)
    let newStartTime = formatTimeToString(editedStartTime)
    let newEndTime = formatTimeToString(editedEndTime)

    // Clear any previous error
    errorMessage = nil

    // Call the update callback
    isSaving = true
    impactHaptic.impactOccurred()

    if let onUpdate = onUpdate {
      // Create the edit result with all necessary information
      let editResult = ShiftEditResult(
        shiftId: shift.id,
        shiftDate: newDate,
        startTime: newStartTime,
        endTime: newEndTime,
        isVirtualShiftConversion: isVirtualShift,
        recurringId: shift.shift.recurring_id,
        originalDate: shift.shiftDate,
        customSupplements: supplementsWereEdited ? editedSupplements : nil
      )
      onUpdate(editResult)
      // The parent will handle dismissing or showing errors
      dismiss()
    } else {
      isSaving = false
      errorMessage = "Update not available"
    }
  }

  // MARK: - Sections

  private var headerSection: some View {
    VStack(spacing: 8) {
      // Large date display
      Text(formattedDate)
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }

  private var timeSection: some View {
    VStack(spacing: 16) {
      // Section header
      HStack {
        Image(systemName: "clock")
          .foregroundColor(.tidexBlue)
        Text(.shiftsTimeSection)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      // Time details card
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(.shiftsTimeRange)
            .font(.system(size: 13))
            .foregroundColor(.tidexTextMuted)
          Text(formattedTimeRange)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.tidexTextPrimary)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 4) {
          Text(.shiftsDuration)
            .font(.system(size: 13))
            .foregroundColor(.tidexTextMuted)
          Text(formattedHours)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.tidexTextPrimary)
        }
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  // MARK: - Editable Time Section

  private var editableTimeSection: some View {
    VStack(spacing: 16) {
      // Section header
      HStack {
        Image(systemName: "pencil")
          .foregroundColor(.tidexBlue)
        Text(.shiftsEditTimeSection)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      // Editable fields card
      VStack(spacing: 16) {
        // Date picker row
        HStack {
          Text(.shiftsDate)
            .font(.system(size: 15))
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

        // Start time row
        HStack {
          Text(.shiftsStartTime)
            .font(.system(size: 15))
            .foregroundColor(.tidexTextSecondary)
          Spacer()
          DatePicker(
            "",
            selection: $editedStartTime,
            displayedComponents: .hourAndMinute
          )
          .labelsHidden()
          .tint(.tidexBlue)
          .disabled(!canEditTimes)
          .opacity(canEditTimes ? 1 : 0.5)
        }

        Divider()

        // End time row
        HStack {
          Text(.shiftsEndTime)
            .font(.system(size: 15))
            .foregroundColor(.tidexTextSecondary)
          Spacer()
          DatePicker(
            "",
            selection: $editedEndTime,
            displayedComponents: .hourAndMinute
          )
          .labelsHidden()
          .tint(.tidexBlue)
          .disabled(!canEditTimes)
          .opacity(canEditTimes ? 1 : 0.5)
        }

        // Info about cross-midnight shifts
        if isCrossMidnightShift {
          HStack(spacing: 8) {
            Image(systemName: "moon.fill")
              .font(.system(size: 12))
              .foregroundColor(.tidexBlue)
            Text(.shiftsCrossMidnightInfo)
              .font(.system(size: 13))
              .foregroundColor(.tidexTextSecondary)
            Spacer()
          }
          .padding(.top, 4)
        }

        // Virtual shift info (will be converted to regular shift)
        if isVirtualShift {
          HStack(spacing: 8) {
            Image(systemName: "info.circle")
              .font(.system(size: 14))
              .foregroundColor(.tidexBlue)
            Text(.shiftsVirtualConversionInfo)
              .font(.system(size: 13))
              .foregroundColor(.tidexTextSecondary)
            Spacer()
          }
          .padding(.top, 4)
        }
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  /// Whether the edited times represent a cross-midnight shift
  private var isCrossMidnightShift: Bool {
    let startStr = formatTimeToString(editedStartTime)
    let endStr = formatTimeToString(editedEndTime)
    return endStr <= startStr && endStr != "00:00"
  }

  // MARK: - Error Banner

  @ViewBuilder
  private func errorBanner(message: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 14))
        .foregroundColor(.tidexError)
      Text(message)
        .font(.system(size: 14))
        .foregroundColor(.tidexError)
      Spacer()
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.tidexError.opacity(0.1))
    )
  }

  // MARK: - Action Buttons

  /// Action buttons for edit mode
  private var editActionButtons: some View {
    VStack(spacing: 12) {
      // Save button
      Button {
        saveChanges()
      } label: {
        HStack(spacing: 8) {
          if isSaving {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .scaleEffect(0.8)
          } else {
            Image(systemName: "checkmark")
              .font(.system(size: 15, weight: .medium))
          }
          Text(.commonSaveChanges)
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(hasChanges ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
        .cornerRadius(12)
      }
      .disabled(isSaving || !hasChanges)

      // Cancel button
      Button {
        cancelEditing()
      } label: {
        Text(.commonCancel)
          .font(.system(size: 15, weight: .medium))
          .foregroundColor(.tidexTextSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexSurfaceSecondary)
          .cornerRadius(12)
      }
      .disabled(isSaving)
    }
    .padding(.top, 8)
  }

  /// Action buttons for view mode
  @ViewBuilder
  private var viewModeActionButtons: some View {
    VStack(spacing: 12) {
      // Edit button (only show if onUpdate callback is provided)
      if onUpdate != nil {
        Button {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isEditing = true
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "pencil")
              .font(.system(size: 15, weight: .medium))
            Text(.shiftsEditButton)
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue)
          .cornerRadius(12)
        }
      }

      // Edit recurring shift button (only for virtual shifts)
      if isVirtualShift, let recurringId = shift.shift.recurring_id, onEditRecurring != nil {
        Button {
          dismiss()
          // Small delay to allow sheet to dismiss before opening editor
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onEditRecurring?(recurringId)
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "repeat")
              .font(.system(size: 15, weight: .medium))
            Text(.shiftsEditRecurringButton)
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundColor(.tidexBlue)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue.opacity(0.1))
          .cornerRadius(12)
        }
      }

      // Delete button
      if let onDelete = onDelete {
        deleteButton(onDelete: onDelete, isVirtual: isVirtualShift)
      }
    }
  }

  private var earningsSection: some View {
    VStack(spacing: 16) {
      // Section header
      HStack {
        Image(systemName: "creditcard")
          .foregroundColor(.tidexBlue)
        Text(.shiftsEarningsSection)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      // Earnings card
      VStack(spacing: 12) {
        // Base Pay (only show when there are supplements)
        if hasSupplementBreakdown {
          earningsRow(
            label: String(localized: .shiftsBasePay),
            value: formatCurrency(shift.computed.basePay)
          )

          Divider()
        }

        // Supplement breakdown section
        if hasSupplementBreakdown {
          supplementBreakdownSection
        }

        // Gross
        earningsRow(
          label: String(localized: .shiftsGrossPay),
          value: formatCurrency(shift.grossPay),
          isHighlighted: !showTaxBreakdown && !hasSupplementBreakdown
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

        // Edit supplements button (always show if tariff rules are available)
        if onUpdate != nil && !tariffRules.isEmpty {
          Divider()

          Button {
            impactHaptic.impactOccurred()
            showingSupplementsEditor = true
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
              Text(.supplementsEditButton)
                .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.tidexBlue)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.tidexBlue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  /// Supplement breakdown showing each time period with supplements
  @ViewBuilder
  private var supplementBreakdownSection: some View {
    VStack(spacing: 12) {
      // Total supplement header with optional "Customized" badge
      HStack {
        HStack(spacing: 8) {
          Text(.shiftsTotalSupplement)
            .font(.system(size: 15))
            .foregroundColor(.tidexTextSecondary)

          if hasCustomSupplements {
            Text(.shiftsCustomized)
              .font(.system(size: 11, weight: .medium))
              .foregroundColor(.tidexBlue)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(
                Capsule()
                  .fill(Color.tidexBlue.opacity(0.15))
              )
          }
        }

        Spacer()

        Text(formatCurrency(shift.computed.supplementPay))
          .font(.system(size: 15, weight: .medium))
          .foregroundColor(.tidexTextPrimary)
      }

      // Individual supplement segments
      ForEach(supplementSegments) { segment in
        supplementSegmentRow(segment)
      }

      Divider()
    }
  }

  /// A single supplement segment row showing time range, hours × rate, and amount
  @ViewBuilder
  private func supplementSegmentRow(_ segment: SupplementSegment) -> some View {
    VStack(spacing: 6) {
      // Time range and hours × rate
      HStack {
        Text(segmentTimeRange(segment))
          .font(.system(size: 14))
          .foregroundColor(.tidexTextPrimary)
          .environment(\.layoutDirection, .leftToRight)

        Spacer()

        Text("\(formatHoursValue(segment.actualHours)) × \(formatCurrency(segment.rate))")
          .font(.system(size: 14))
          .foregroundColor(.tidexTextSecondary)
      }

      // Supplement label and amount
      HStack {
        Text(.shiftsSupplementLabel)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Text(formatCurrency(segment.amount))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.tidexTextPrimary)
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.tidexSurfaceSecondary.opacity(0.4))
    )
  }

  /// Format hours value (e.g., "2.50 t")
  private func formatHoursValue(_ hours: Double) -> String {
    return String(format: "%.2f t", hours)
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
    HStack {
      Text(label)
        .font(.system(size: 15, weight: isHighlighted ? .medium : .regular))
        .foregroundColor(isHighlighted ? .tidexTextPrimary : .tidexTextSecondary)

      Spacer()

      Text(value)
        .font(.system(size: isHighlighted ? 20 : 15, weight: isHighlighted ? .semibold : .medium))
        .foregroundColor(valueColor)
    }
  }

  private var virtualShiftBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "repeat")
        .font(.system(size: 16))
        .foregroundColor(.tidexBlue)

      VStack(alignment: .leading, spacing: 2) {
        Text(.shiftsRecurringShift)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.tidexTextPrimary)
        Text(.shiftsRecurringShiftDescription)
          .font(.system(size: 13))
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.tidexBlue.opacity(0.1))
    )
  }

  @ViewBuilder
  private func deleteButton(onDelete: @escaping () -> Void, isVirtual: Bool) -> some View {
    Button(action: onDelete) {
      HStack(spacing: 8) {
        Image(systemName: isVirtual ? "minus.circle" : "trash")
          .font(.system(size: 15, weight: .medium))
        Text(
          isVirtual
            ? String(localized: .shiftsExcludeButton)
            : String(localized: .shiftsDeleteButton)
        )
        .font(.system(size: 15, weight: .semibold))
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexError)
      .cornerRadius(12)
    }
    .padding(.top, 8)
  }

  /// Footer showing when the shift was last edited
  @ViewBuilder
  private func lastEditedFooter(date: Date) -> some View {
    Text(String(localized: .shiftsLastEdited) + " " + formattedLastEdited(date))
      .font(.system(size: 12))
      .foregroundColor(.tidexTextMuted)
      .frame(maxWidth: .infinity)
      .padding(.top, 8)
  }

  /// Format the last edited date with relative or absolute formatting
  private func formattedLastEdited(_ date: Date) -> String {
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
}

// MARK: - Share Options Sheet

/// Bottom sheet for selecting share options
private struct ShareOptionsSheet: View {
  let onShowEarnings: () -> Void
  let onHideEarnings: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 20) {
      // Title
      Text(.shiftsShareTitle)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.tidexTextPrimary)
        .padding(.top, 16)

      VStack(spacing: 12) {
        // Show earnings option
        Button {
          onShowEarnings()
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "eye")
              .font(.system(size: 20, weight: .medium))
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(.shiftsShareShowEarnings)
              .font(.system(size: 17, weight: .medium))
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)

        // Hide earnings option
        Button {
          onHideEarnings()
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "eye.slash")
              .font(.system(size: 20, weight: .medium))
              .foregroundColor(.tidexBlue)
              .frame(width: 28)
            Text(.shiftsShareHideEarnings)
              .font(.system(size: 17, weight: .medium))
              .foregroundColor(.tidexTextPrimary)
            Spacer()
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 18)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(Color.tidexSurfacePrimary)
          )
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 20)

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }
}

// MARK: - Supplement Segment

/// A grouped supplement segment for display
struct SupplementSegment: Identifiable {
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
