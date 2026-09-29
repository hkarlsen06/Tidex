import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WageSnapshotEditorSheet")

// MARK: - Wage Snapshot Editor Sheet

enum WageSnapshotEditorSection: Hashable {
  case wage, supplements, overtime, tax, breaks
}

/// Sheet for creating or editing a wage snapshot
struct WageSnapshotEditorSheet: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  let mode: PaySettingsViewModel.EditorMode
  let snapshot: WageSnapshot?
  let snapshots: [WageSnapshot]
  /// User's currency from settings
  let userCurrency: String
  let saveError: String?
  let initialSection: WageSnapshotEditorSection?
  let onSave: (WageSnapshotEditorInput) async -> Bool
  let onDelete: (WageSnapshot) -> Void
  let onCancel: () -> Void

  // Form state
  @State private var fromDate = Date()  // swiftlint:disable:this explicit_type_interface
  @State private var usePreset: Bool = true
  @State private var wageLevel: Int = 1
  @State private var customWage: Double = 200
  @State private var supplements: [OnboardingSupplementRule] = []
  @State private var overtimeEnabled: Bool = false
  @State private var overtimeThresholdHours: Double = OvertimeConfig.defaultWeeklyThresholdHours
  @State private var overtimeRules: [OvertimeRuleDraft] = []
  @State private var breakEnabled: Bool = true
  @State private var breakMethod: BreakMethod = .proportional
  @State private var breakThresholdHours: Double = 5.5
  @State private var breakDeductionMinutes: Int = 30
  @State private var taxEnabled: Bool = false
  @State private var taxPercentage: Double = 0
  @State private var inheritedSnapshot: WageSnapshot?
  @State private var usesSavedTariffRates = false
  @State private var savedTariffSupplements = SupplementRulesSnapshot(rules: [])
  @State private var shouldApplyTariffOvertime = false

  @State private var isSaving = false
  @State private var errorMessage: String?

  // Supplements editor
  @State private var showingSupplementEditor = false
  @State private var editingSupplementRule: OnboardingSupplementRule?

  // Tariff versioning state
  @State private var tariffTypes: [TariffType] = []
  @State private var tariffVersion: TariffVersion?
  @State private var tariffTypeName: String?
  @State private var tariffTypeId: String?
  @State private var isLoadingTariff = false

  private var isBaseline: Bool {
    snapshot?.isBaseline ?? false
  }

  /// Whether tariff option is available (only for Norwegian krone)
  private var showTariffOption: Bool {
    userCurrency == "kr"
  }

  private var currency: String {
    userCurrency
  }

  /// Display name for the current tariff version (e.g., "HK Detaljhandel - 2024")
  private var tariffVersionDisplayName: String? {
    guard let version = tariffVersion, let typeName = tariffTypeName else { return nil }
    let year = String(version.effective_date.prefix(4))
    return "\(typeName) - \(year)"
  }

  init(
    mode: PaySettingsViewModel.EditorMode,
    snapshot: WageSnapshot?,
    snapshots: [WageSnapshot],
    initialDate: Date = Date(),
    userCurrency: String = "kr",
    saveError: String? = nil,
    initialSection: WageSnapshotEditorSection? = nil,
    onSave: @escaping (WageSnapshotEditorInput) async -> Bool,
    onDelete: @escaping (WageSnapshot) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.mode = mode
    self.snapshot = snapshot
    self.snapshots = snapshots
    self.userCurrency = userCurrency
    self.saveError = saveError
    self.initialSection = initialSection
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel

    // Tariff is only available for Norwegian krone
    let canUseTariff = userCurrency == "kr"

    let source =
      mode == .edit
      ? snapshot
      : SnapshotsService.snapshotForDate(
        initialDate.toISODateString(), from: snapshots
      )
    _fromDate = State(
      initialValue: mode == .edit
        ? source?.from_date.flatMap { Date.fromISODateString($0) } ?? initialDate : initialDate)
    _inheritedSnapshot = State(initialValue: source)

    if let source {
      _usePreset = State(initialValue: canUseTariff && source.wage_level != nil)
      _wageLevel = State(initialValue: source.wage_level ?? 1)
      _customWage = State(initialValue: source.hourly_wage)
      _supplements = State(
        initialValue: source.supplements.rules.map(OnboardingSupplementRule.init))
      _overtimeEnabled = State(initialValue: source.overtime.enabled)
      _overtimeThresholdHours = State(initialValue: source.overtime.weeklyThresholdHours)
      _overtimeRules = State(initialValue: source.overtime.rules.map(OvertimeRuleDraft.init))
      _breakEnabled = State(
        initialValue: source.effectiveBreakEnabled && source.breakMethod != .none)
      _breakMethod = State(initialValue: source.breakMethod)
      _breakThresholdHours = State(initialValue: source.effectiveBreakThresholdHours)
      _breakDeductionMinutes = State(initialValue: source.effectiveBreakDeductionMinutes)
      _taxEnabled = State(initialValue: source.effectiveTaxEnabled)
      _taxPercentage = State(initialValue: source.effectiveTaxPercentage)
      _tariffTypeId = State(initialValue: source.tariff_type_id)
      _usesSavedTariffRates = State(initialValue: source.wage_level != nil)
      _savedTariffSupplements = State(initialValue: source.supplements)
    } else {
      // No existing snapshot - default to custom wage if tariff not available
      _usePreset = State(initialValue: canUseTariff)
      let defaultOvertime = canUseTariff ? PayrollCalculator.presetOvertimeConfig : .disabled
      _overtimeEnabled = State(initialValue: defaultOvertime.enabled)
      _overtimeThresholdHours = State(initialValue: defaultOvertime.weeklyThresholdHours)
      _overtimeRules = State(initialValue: defaultOvertime.rules.map { OvertimeRuleDraft($0) })
    }
  }

  var body: some View {
    NavigationStack {
      editorContent
        .navigationTitle(
          mode == .create
            ? String(localized: .settingsPayEditorCreateTitle)
            : String(localized: .settingsPayEditorEditTitle)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingSupplementEditor) {
          supplementEditorSheet
        }
        .interactiveDismissDisabled(isSaving)
        .task {
          await loadTariffVersion()
        }
        .task(id: tariffLookupID) {
          await loadTariffVersionForDate(fromDate)
        }
        .onChange(of: fromDate) { _, newDate in
          rebaseInheritedSettings(for: newDate)
        }
        .onChange(of: overtimeEnabled) { _, enabled in
          if enabled, overtimeRules.isEmpty {
            overtimeThresholdHours = OvertimeConfig.defaultWeeklyThresholdHours
            overtimeRules = OvertimeConfig.seededDefaults.rules.map { OvertimeRuleDraft($0) }
          }
        }
    }
  }

  private var editorContent: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      ScrollViewReader { proxy in
        ScrollView {
          editorSections
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
          if let initialSection {
            proxy.scrollTo(initialSection, anchor: .top)
          }
        }
      }
    }
  }

  private var editorSections: some View {
    VStack(spacing: Spacing.lg) {
      // Date section (or baseline indicator)
      dateSection

      Divider()
        .padding(.horizontal)

      // Wage source selector
      wageSourceSelector
        .padding(.horizontal)
        .id(WageSnapshotEditorSection.wage)

      Divider()
        .padding(.horizontal)

      // Supplements section
      supplementsSection

      Divider()
        .padding(.horizontal)

      // Overtime section
      OvertimeEditorSection(
        enabled: $overtimeEnabled,
        thresholdHours: $overtimeThresholdHours,
        rules: $overtimeRules
      )
      .id(WageSnapshotEditorSection.overtime)

      Divider()
        .padding(.horizontal)

      deductionSections

      if mode == .edit, !isBaseline {
        Divider()
          .padding(.horizontal, Spacing.md)
        deleteButton
          .padding(.horizontal, Spacing.md)
      }

      // Error message
      if let error = errorMessage ?? saveError {
        errorBanner(error)
          .padding(.horizontal)
      }
    }
    .padding(.vertical, Spacing.lg)
  }

  private var supplementsSection: some View {
    SupplementsEditorSection(
      usePreset: usePreset,
      presetRules: resolvedSupplements.rules,
      supplements: $supplements,
      currency: currency,
      onAdd: {
        editingSupplementRule = nil
        showingSupplementEditor = true
      },
      onEdit: { rule in
        editingSupplementRule = rule
        showingSupplementEditor = true
      }
    )
    .id(WageSnapshotEditorSection.supplements)
  }

  private var deductionSections: some View {
    Group {
      // Tax deduction section
      TaxDeductionSection(
        enabled: $taxEnabled,
        percentage: $taxPercentage
      )
      .padding(.horizontal)
      .id(WageSnapshotEditorSection.tax)

      Divider()
        .padding(.horizontal)

      // Break deduction section
      BreakDeductionSection(
        enabled: $breakEnabled,
        method: $breakMethod,
        thresholdHours: $breakThresholdHours,
        deductionMinutes: $breakDeductionMinutes
      )
      .padding(.horizontal)
      .id(WageSnapshotEditorSection.breaks)
    }
  }

  private var wageSourceSelector: some View {
    WageSourceSelector(
      usePreset: Binding(
        get: { usePreset },
        set: {
          guard usePreset != $0 else { return }
          usePreset = $0
          usesSavedTariffRates = false
        }
      ),
      wageLevel: Binding(
        get: { wageLevel },
        set: {
          guard wageLevel != $0 else { return }
          wageLevel = $0
          usesSavedTariffRates = false
        }
      ),
      customWage: $customWage,
      currency: currency,
      showTariffOption: showTariffOption,
      tariffVersion: tariffVersion,
      savedTariffRate: usesSavedTariffRates ? customWage : nil,
      selectorFooterContent: showTariffOption && usePreset
        ? AnyView(tariffVersionIndicator)
        : nil
    )
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button(String(localized: .commonCancel)) {
        onCancel()
      }
      .disabled(isSaving)
    }
    ToolbarItem(placement: .confirmationAction) {
      Button(String(localized: .commonSave)) {
        Task { await save() }
      }
      .disabled(!canSave || isSaving)
      .fontWeight(.semibold)
    }
  }

  private var supplementEditorSheet: some View {
    SupplementRuleEditor(
      rule: editingSupplementRule,
      currency: currency,
      onSave: { rule in
        if let editingRule = editingSupplementRule {
          // Update existing rule
          if let index = supplements.firstIndex(where: { $0.id == editingRule.id }) {
            supplements[index] = rule
          }
        } else {
          // Add new rule
          supplements.append(rule)
        }
        showingSupplementEditor = false
        editingSupplementRule = nil
      },
      onCancel: {
        showingSupplementEditor = false
        editingSupplementRule = nil
      }
    )
  }

  // MARK: - Tariff Version Loading

  private var tariffLookupID: String {
    "\(tariffTypeId ?? ""): \(fromDate.toISODateString())"
  }

  /// Load tariff version based on mode and date
  private func loadTariffVersion() async {
    guard showTariffOption else { return }

    do {
      // First, load all available tariff types
      let types = try await TariffVersionService.shared.getTariffTypes()
      tariffTypes = types

      // Get the tariff type ID to use
      let effectiveTariffTypeId: String

      if let existingTypeId = tariffTypeId {
        // Use existing tariff type from snapshot
        effectiveTariffTypeId = existingTypeId
      } else {
        // Get default tariff type
        guard let defaultType = types.first(where: \.is_default) ?? types.first else {
          logger.warning("No default tariff type found")
          return
        }
        effectiveTariffTypeId = defaultType.id
        tariffTypeId = effectiveTariffTypeId
        tariffTypeName = defaultType.display_name
      }

      // Load tariff type name if not set
      if tariffTypeName == nil {
        tariffTypeName = types.first { $0.id == effectiveTariffTypeId }?.display_name
      }

    } catch {
      logger.error("Failed to load tariff version: \(error.localizedDescription)")
    }
  }

  /// Reload tariff version for a specific date (when date picker changes)
  private func loadTariffVersionForDate(_ date: Date) async {
    guard showTariffOption, let typeId = tariffTypeId else { return }

    isLoadingTariff = true
    tariffVersion = nil
    defer {
      if !Task.isCancelled { isLoadingTariff = false }
    }

    let isoDate = date.toISODateString()

    do {
      let version = try await TariffVersionService.shared.getTariffVersionForDate(
        tariffType: typeId,
        date: isoDate
      )
      guard !Task.isCancelled, tariffTypeId == typeId,
        fromDate.toISODateString() == isoDate
      else { return }
      tariffVersion = version
      applyTariffOvertimeDefaultIfNeeded(force: shouldApplyTariffOvertime)
      shouldApplyTariffOvertime = false
      logger.info(
        "Reloaded tariff version for date \(isoDate): \(tariffVersion?.effective_date ?? "none")")
    } catch {
      guard !Task.isCancelled else { return }
      logger.error("Failed to reload tariff version for date: \(error.localizedDescription)")
    }
  }

  // MARK: - Can Save

  private var canSave: Bool {
    guard !hasDateConflict else { return false }
    guard currentOvertimeConfig.isValidForEditing else {
      return false
    }
    if usePreset {
      return usesSavedTariffRates
        || (!isLoadingTariff && tariffVersion?.rate(forLevel: wageLevel) != nil)
    }
    return customWage.isFinite && customWage > 0
  }

  private var currentOvertimeConfig: OvertimeConfig {
    OvertimeConfig(
      enabled: overtimeEnabled,
      weeklyThresholdHours: overtimeThresholdHours,
      rules: overtimeRules.map { $0.toRule() }
    )
  }

  private func applyTariffOvertimeDefaultIfNeeded(force: Bool = false) {
    guard showTariffOption, usePreset else { return }
    guard force || (snapshot == nil && inheritedSnapshot == nil) else { return }
    let defaultOvertime = tariffVersion?.effectiveOvertime ?? PayrollCalculator.presetOvertimeConfig
    overtimeEnabled = defaultOvertime.enabled
    overtimeThresholdHours = defaultOvertime.weeklyThresholdHours
    overtimeRules = defaultOvertime.rules.map { OvertimeRuleDraft($0) }
  }

  // MARK: - Tariff Version Indicator

  @ViewBuilder
  private var tariffVersionIndicator: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      // Tariff type picker - always show when tariff types are loaded
      if !tariffTypes.isEmpty {
        tariffTypePicker
      }

      // Tariff version info (effective date)
      if let version = tariffVersion {
        ViewThatFits(in: .horizontal) {
          effectiveDateRow(version, isStacked: false)
          effectiveDateRow(version, isStacked: true)
        }
      } else if isLoadingTariff {
        HStack(spacing: Spacing.xs) {
          ProgressView()
            .scaleEffect(0.7)
          Text(.settingsPayEditorLoadingTariff)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
          Spacer()
        }
      }

      tariffRatesStatus
    }
  }

  @ViewBuilder
  private func effectiveDateRow(_ version: TariffVersion, isStacked: Bool) -> some View {
    let layout = isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
      : AnyLayout(HStackLayout(spacing: Spacing.xs))
    layout {
      Image(systemName: "calendar")
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
        .accessibilityHidden(true)

      Text(.settingsPayEditorTariffEffectiveDate)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)

      Text(formatEffectiveDate(version.effective_date))
        .font(.tidexCaption)
        .foregroundColor(.tidexTextSecondary)

      if !isStacked {
        Spacer()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var tariffTypePicker: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(.settingsPayEditorTariffTypeLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Picker(
        "",
        selection: Binding(
          get: { tariffTypeId ?? "" },
          set: { newValue in
            guard newValue != tariffTypeId else { return }
            tariffTypeId = newValue
            tariffTypeName = tariffTypes.first { $0.id == newValue }?.display_name
            wageLevel = 1
            usesSavedTariffRates = false
            shouldApplyTariffOvertime = true
          }
        )
      ) {
        ForEach(tariffTypes) { type in
          Text(type.display_name)
            .tag(type.id)
        }
      }
      .pickerStyle(.menu)
      .accessibilityLabel(Text(.settingsPayEditorTariffTypeLabel))
      .tint(.tidexBlueText)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
    }
  }

  @ViewBuilder
  private var tariffRatesStatus: some View {
    if usesSavedTariffRates {
      Text(.settingsPayEditorSavedTariff)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
      Button(String(localized: .settingsPayEditorRefreshTariff)) {
        usesSavedTariffRates = false
        applyTariffOvertimeDefaultIfNeeded(force: true)
      }
      .disabled(isLoadingTariff || tariffVersion?.rate(forLevel: wageLevel) == nil)
    } else if !isLoadingTariff, tariffVersion?.rate(forLevel: wageLevel) == nil {
      Text(.settingsPayEditorTariffUnavailable)
        .font(.tidexFootnote)
        .foregroundColor(.tidexWarning)
      Button(String(localized: .commonRetry)) {
        Task {
          await loadTariffVersion()
          await loadTariffVersionForDate(fromDate)
        }
      }
    }
  }

  /// Format effective date for display
  private func formatEffectiveDate(_ isoDate: String) -> String {
    guard let date = Date.fromISODateString(isoDate) else { return isoDate }

    let displayFormatter = DateFormatter()
    displayFormatter.dateFormat = "MMMM yyyy"
    return displayFormatter.string(from: date)
  }

  // MARK: - Date Section

  @ViewBuilder
  private var dateSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.settingsPayEditorFromDateLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      if isBaseline {
        // Baseline indicator
        HStack {
          Image(systemName: "clock.arrow.circlepath")
            .foregroundColor(.tidexTextSecondary)
            .accessibilityHidden(true)

          Text(.settingsPayEditorBaselineIndicator)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextPrimary)

          Spacer()
        }

        Text(.settingsPayEditorBaselineHelp)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      } else {
        // Date picker
        DatePicker(selection: $fromDate, displayedComponents: .date) {
          Text(.settingsPayEditorFromDateLabel)
        }
        .labelsHidden()
        .datePickerStyle(.compact)
        .accessibilityLabel(Text(.settingsPayEditorFromDateLabel))
        .tint(.tidexBlueText)
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(.settingsPayEditorFromDateHelp)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      dateNotes
    }
    .padding(.horizontal)
  }

  @ViewBuilder
  private var dateNotes: some View {
    Text(mode == .edit ? .settingsPayEditorEditImpact : .settingsPayEditorCreateImpact)
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextSecondary)
      .fixedSize(horizontal: false, vertical: true)

    if let nextDate = nextChangeDate {
      Text(
        .settingsPayEditorNextChange(
          nextDate.formatted(.dateTime.day().month().year().calendar(.gregorian)))
      )
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }

    if hasDateConflict {
      Text(.settingsPayEditorDateConflictHelp)
        .font(.tidexFootnote)
        .foregroundColor(.tidexError)
        .announcesToVoiceOver(String(localized: .settingsPayEditorDateConflictHelp))
    }
  }

  // MARK: - Error Banner

  @ViewBuilder
  private func errorBanner(_ message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexError)
        .accessibilityHidden(true)

      Text(message)
        .font(.tidexFootnote)
        .foregroundColor(.tidexError)

      Spacer()
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
    .announcesToVoiceOver(message)
  }

  // MARK: - Delete Button

  @ViewBuilder
  private var deleteButton: some View {
    Button(action: {
      Haptics.play(.medium)
      if let snapshot {
        onDelete(snapshot)
      }
    }) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "trash")
          .font(.tidexBody)
          .accessibilityHidden(true)

        Text(.settingsPayEditorDelete)
          .font(.tidexButton)
      }
      .foregroundColor(.tidexError)
      .frame(maxWidth: .infinity, minHeight: Spacing.buttonHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isSaving)
  }

  // MARK: - Save

  private var hasDateConflict: Bool {
    guard !isBaseline else { return false }
    return snapshots.contains {
      $0.id != snapshot?.id && $0.from_date == fromDate.toISODateString()
    }
  }

  private var nextChangeDate: Date? {
    snapshots.filter { $0.id != snapshot?.id }
      .compactMap(\.from_date)
      .filter { isBaseline || $0 > fromDate.toISODateString() }
      .min()
      .flatMap { Date.fromISODateString($0) }
  }

  private var resolvedSupplements: SupplementRulesSnapshot {
    guard showTariffOption, usePreset else {
      return SupplementRulesSnapshot(rules: supplements.map { $0.toSupplementRule() })
    }
    if usesSavedTariffRates { return savedTariffSupplements }
    return tariffVersion?.supplements ?? SupplementRulesSnapshot(rules: [])
  }

  private var editorInput: WageSnapshotEditorInput {
    let effectiveUsePreset = showTariffOption && usePreset
    let wage =
      effectiveUsePreset && !usesSavedTariffRates
      ? tariffVersion?.rate(forLevel: wageLevel) ?? customWage : customWage
    return WageSnapshotEditorInput(
      fromDate: isBaseline ? nil : fromDate,
      hourlyWage: wage,
      wageLevel: effectiveUsePreset ? wageLevel : nil,
      supplements: resolvedSupplements,
      overtime: currentOvertimeConfig,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: breakEnabled && breakMethod == .none ? .proportional : breakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes,
      tariffTypeId: effectiveUsePreset
        ? (usesSavedTariffRates ? inheritedSnapshot?.tariff_type_id : tariffTypeId) : nil
    )
  }

  private func rebaseInheritedSettings(for date: Date) {
    guard mode == .create, let previous = inheritedSnapshot,
      let next = SnapshotsService.snapshotForDate(date.toISODateString(), from: snapshots),
      previous.id != next.id
    else { return }

    let current = editorInput
    let inheritsWage =
      current.hourlyWage == previous.hourly_wage
      && current.wageLevel == previous.wage_level && current.tariffTypeId == previous.tariff_type_id
    let input = current.rebasingUneditedSettings(from: previous, onto: next)
    inheritedSnapshot = next
    usePreset = showTariffOption && input.wageLevel != nil
    wageLevel = input.wageLevel ?? 1
    customWage = input.hourlyWage
    supplements = input.supplements.rules.map(OnboardingSupplementRule.init)
    savedTariffSupplements = input.supplements
    tariffTypeId = input.tariffTypeId
    if inheritsWage { usesSavedTariffRates = usePreset }
    overtimeEnabled = input.overtime.enabled
    overtimeThresholdHours = input.overtime.weeklyThresholdHours
    overtimeRules = input.overtime.rules.map(OvertimeRuleDraft.init)
    taxEnabled = input.taxEnabled
    taxPercentage = input.taxPercentage
    breakEnabled = input.breakEnabled
    breakMethod = input.breakMethod
    breakThresholdHours = input.breakThresholdHours
    breakDeductionMinutes = input.breakDeductionMinutes
  }

  private func save() async {
    guard canSave, !isSaving else { return }
    isSaving = true
    errorMessage = nil
    let success = await onSave(editorInput)

    if !success {
      // Error message should be set by the view model
      isSaving = false
    }
  }
}

// MARK: - OnboardingSupplementRule Extension

extension OnboardingSupplementRule {
  /// Create from a SupplementRule
  init(from rule: SupplementRule) {
    // Convert day format: SupplementRule uses 0-6 (Sunday-Saturday), OnboardingSupplementRule uses 1-7 (Monday-Sunday)
    let convertedDays = Set(
      rule.days.map { day -> Int in
        // Convert 0-6 (Sun-Sat) to 1-7 (Mon-Sun)
        if day == 0 {
          return 7
        }
        return day
      })

    self.id = UUID()
    self.days = convertedDays
    self.fromTime = rule.from
    self.toTime = rule.to
    self.type = rule.rate != nil ? .fixed : .percent
    self.value = rule.rate ?? rule.percent ?? 0
  }
}

// MARK: - Preview

#Preview("Create Mode") {
  WageSnapshotEditorSheet(
    mode: .create,
    snapshot: nil,
    snapshots: [],
    onSave: { _ in true },
    onDelete: { _ in },
    onCancel: {}
  )
}
