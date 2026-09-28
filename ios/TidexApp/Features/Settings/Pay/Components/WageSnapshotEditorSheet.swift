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
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        ScrollViewReader { proxy in
          ScrollView {
            VStack(spacing: Spacing.lg) {
              // Date section (or baseline indicator)
              dateSection

              Divider()
                .padding(.horizontal)

              // Wage source selector
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
              .padding(.horizontal)
              .id(WageSnapshotEditorSection.wage)

              Divider()
                .padding(.horizontal)

              // Supplements section
              supplementsSection
                .id(WageSnapshotEditorSection.supplements)

              Divider()
                .padding(.horizontal)

              // Overtime section
              overtimeSection
                .id(WageSnapshotEditorSection.overtime)

              Divider()
                .padding(.horizontal)

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
          .scrollDismissesKeyboard(.interactively)
          .onAppear {
            if let initialSection {
              proxy.scrollTo(initialSection, anchor: .top)
            }
          }
        }
      }
      .navigationTitle(
        mode == .create
          ? String(localized: .settingsPayEditorCreateTitle)
          : String(localized: .settingsPayEditorEditTitle)
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
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
      .sheet(isPresented: $showingSupplementEditor) {
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
          .tint(.tidexBrandPrimary)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xs)
          .background(Color.tidexSurfaceSecondary)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        }
      }

      // Tariff version info (effective date)
      if let version = tariffVersion {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "calendar")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)

          Text(.settingsPayEditorTariffEffectiveDate)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)

          Text(formatEffectiveDate(version.effective_date))
            .font(.tidexCaption)
            .foregroundColor(.tidexTextSecondary)

          Spacer()
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
        .tint(.tidexBrandPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(.settingsPayEditorFromDateHelp)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }

      Text(mode == .edit ? .settingsPayEditorEditImpact : .settingsPayEditorCreateImpact)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      if let nextDate = nextChangeDate {
        Text(
          .settingsPayEditorNextChange(
            nextDate.formatted(.dateTime.day().month().year().calendar(.gregorian))))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if hasDateConflict {
        Text(.settingsPayEditorDateConflictHelp)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
      }
    }
    .padding(.horizontal)
  }

  // MARK: - Supplements Section

  @ViewBuilder
  private var supplementsSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        Text(.settingsPayEditorSupplementsTitle)
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        if !usePreset {
          Button(action: {
            editingSupplementRule = nil
            showingSupplementEditor = true
          }) {
            Image(systemName: "plus")
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexBlue)
              .frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel(Text(.supplementsAddRule))
        }
      }

      if usePreset {
        // Read-only preset supplements (from tariff version or fallback)
        Text(.settingsPayEditorSupplementsTariff)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)

        let presetRules = resolvedSupplements.rules
        ForEach(presetRules.indices, id: \.self) { index in
          presetSupplementRow(presetRules[index])
        }
      } else {
        // Editable custom supplements
        if supplements.isEmpty {
          Text(.settingsPayEditorSupplementsEmpty)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        } else {
          ForEach(supplements) { rule in
            customSupplementRow(rule)
          }
        }
      }
    }
    .padding(.horizontal)
    .sensoryFeedback(.impact(weight: .light), trigger: supplements.count)
  }

  @ViewBuilder
  private func presetSupplementRow(_ rule: SupplementRule) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(formatDays(rule.days))
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)

        Text("\(rule.from) - \(rule.to)")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      Text(formatRuleValue(rule))
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBrandPrimary)
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
  }

  @ViewBuilder
  private func customSupplementRow(_ rule: OnboardingSupplementRule) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(rule.daysDescription)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)

        Text(rule.timeDescription)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      Text(rule.valueDescription(locale: Locale.current, currency: currency))
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBrandPrimary)

      // Edit button
      Button(action: {
        editingSupplementRule = rule
        showingSupplementEditor = true
      }) {
        Image(systemName: "pencil")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }
      .accessibilityLabel(
        Text(.supplementsEditRuleAccessibility("\(rule.daysDescription), \(rule.timeDescription)")))

      // Delete button
      Button(action: {
        withAnimation {
          supplements.removeAll { $0.id == rule.id }
        }
      }) {
        Image(systemName: "trash")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexError)
      }
      .accessibilityLabel(
        Text(
          .supplementsDeleteRuleAccessibility("\(rule.daysDescription), \(rule.timeDescription)")))
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
  }

  private func formatDays(_ days: [Int]) -> String {
    let sortedDays = days.sorted()

    if sortedDays == [1, 2, 3, 4, 5] {
      return String(localized: .daysWeekdays)
    }
    if sortedDays == [6, 7] || sortedDays == [0, 6] {  // swiftlint:disable:this no_magic_numbers
      return String(localized: .daysWeekend)
    }
    if sortedDays == Array(1...7) || sortedDays == Array(0...6) {  // swiftlint:disable:this no_magic_numbers
      return String(localized: .daysAllDays)
    }

    let dayNames = [
      String(localized: .daysShortSun),
      String(localized: .daysShortMon),
      String(localized: .daysShortTue),
      String(localized: .daysShortWed),
      String(localized: .daysShortThu),
      String(localized: .daysShortFri),
      String(localized: .daysShortSat),
    ]

    return sortedDays.map { dayNames[$0 % 7] }.joined(separator: ", ")
  }

  private func formatRuleValue(_ rule: SupplementRule) -> String {
    OnboardingSupplementRule(from: rule).valueDescription(locale: .appLocale, currency: currency)
  }

  // MARK: - Overtime Section

  @ViewBuilder
  private var overtimeSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Toggle(isOn: $overtimeEnabled) {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(.settingsPayEditorOvertimeTitle)
            .font(.tidexButton)
            .foregroundColor(.tidexTextPrimary)

          Text(.settingsPayEditorOvertimeSubtitle)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextSecondary)
        }
      }
      .tint(.tidexBrandPrimary)

      if overtimeEnabled {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(.settingsPayEditorOvertimeThreshold)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)

          TextField(
            "",
            value: $overtimeThresholdHours,
            format: .number.precision(.fractionLength(0...2))
          )
          .keyboardType(.decimalPad)
          .textFieldStyle(.roundedBorder)
        }

        ForEach($overtimeRules) { $rule in
          overtimeRuleRow(rule: $rule)
        }

        Button {
          overtimeRules.append(
            OvertimeRuleDraft(
              days: Set(1...7),
              appliesOnHolidays: false,
              from: "00:00",
              to: "24:00",
              percent: 50
            ))
        } label: {
          Label(String(localized: .settingsPayEditorOvertimeAddRule), systemImage: "plus")
            .font(.tidexLabel)
        }
        .buttonStyle(.borderless)
        .tint(.tidexBrandPrimary)
      }
    }
    .padding(.horizontal)
  }

  @ViewBuilder
  private func overtimeRuleRow(rule: Binding<OvertimeRuleDraft>) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        ForEach(1...7, id: \.self) { day in
          Button {
            if rule.wrappedValue.days.contains(day) {
              rule.wrappedValue.days.remove(day)
            } else {
              rule.wrappedValue.days.insert(day)
            }
          } label: {
            Text(dayShortName(day))
              .font(.tidexCaption)
              .foregroundColor(
                rule.wrappedValue.days.contains(day) ? .tidexTextOnBrand : .tidexTextSecondary
              )
              .frame(width: 30, height: 28)
              .background(
                rule.wrappedValue.days.contains(day)
                  ? Color.tidexBrandPrimary
                  : Color.tidexSurfaceSecondary
              )
              .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }

      Toggle(isOn: rule.appliesOnHolidays) {
        Text(.settingsPayEditorOvertimeHolidayToggle)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
      .tint(.tidexBrandPrimary)

      HStack(spacing: Spacing.xs) {
        TextField(String(localized: .settingsPayEditorOvertimeFrom), text: rule.from)
          .textInputAutocapitalization(.never)
          .keyboardType(.numbersAndPunctuation)
          .textFieldStyle(.roundedBorder)

        TextField(String(localized: .settingsPayEditorOvertimeTo), text: rule.to)
          .textInputAutocapitalization(.never)
          .keyboardType(.numbersAndPunctuation)
          .textFieldStyle(.roundedBorder)

        TextField(
          String(localized: .settingsPayEditorOvertimePercent),
          value: rule.percent,
          format: .number.precision(.fractionLength(0...1))
        )
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)

        Button {
          overtimeRules.removeAll { $0.id == rule.wrappedValue.id }
        } label: {
          Image(systemName: "trash")
            .foregroundColor(.tidexError)
            .accessibilityHidden(true)
        }
        .accessibilityLabel(Text(.commonDelete))
        .buttonStyle(.plain)
      }
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
  }

  private func dayShortName(_ day: Int) -> String {
    switch day {
    case 1: String(localized: .daysShortMon)
    case 2: String(localized: .daysShortTue)
    case 3: String(localized: .daysShortWed)
    case 4: String(localized: .daysShortThu)
    case 5: String(localized: .daysShortFri)
    case 6: String(localized: .daysShortSat)
    default: String(localized: .daysShortSun)
    }
  }

  // MARK: - Error Banner

  @ViewBuilder
  private func errorBanner(_ message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexError)

      Text(message)
        .font(.tidexFootnote)
        .foregroundColor(.tidexError)

      Spacer()
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
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

private struct OvertimeRuleDraft: Identifiable, Equatable {
  let id: UUID
  var days: Set<Int>
  var appliesOnHolidays: Bool
  var from: String
  var to: String
  var percent: Double

  init(
    id: UUID = UUID(),
    days: Set<Int>,
    appliesOnHolidays: Bool,
    from: String,
    to: String,
    percent: Double
  ) {
    self.id = id
    self.days = days
    self.appliesOnHolidays = appliesOnHolidays
    self.from = from
    self.to = to
    self.percent = percent
  }

  init(_ rule: OvertimeRule) {
    id = UUID()
    days = Set(rule.days)
    appliesOnHolidays = rule.appliesOnHolidays
    from = rule.from
    to = rule.to
    percent = rule.percent
  }

  func toRule() -> OvertimeRule {
    OvertimeRule(
      days: Array(days).sorted(),
      appliesOnHolidays: appliesOnHolidays,
      from: from,
      to: to,
      percent: percent
    )
  }
}

// MARK: - WageSnapshotEditorInput Extension

extension WageSnapshotEditorInput {
  /// Create input with explicit values (for editor sheet)
  init(
    fromDate: Date?,
    hourlyWage: Double,
    wageLevel: Int?,
    supplements: SupplementRulesSnapshot,
    overtime: OvertimeConfig = .disabled,
    taxEnabled: Bool,
    taxPercentage: Double,
    breakEnabled: Bool,
    breakMethod: BreakMethod,
    breakThresholdHours: Double,
    breakDeductionMinutes: Int,
    tariffTypeId: String? = nil
  ) {
    self.fromDate = fromDate
    self.hourlyWage = hourlyWage
    self.wageLevel = wageLevel
    self.supplements = supplements
    self.overtime = overtime
    self.taxEnabled = taxEnabled
    self.taxPercentage = taxPercentage
    self.breakEnabled = breakEnabled
    self.breakMethod = breakMethod
    self.breakThresholdHours = breakThresholdHours
    self.breakDeductionMinutes = breakDeductionMinutes
    self.tariffTypeId = tariffTypeId
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
