import os.log
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.tidex.app", category: "WageSnapshotEditorSheet")

// MARK: - Wage Snapshot Editor Sheet

/// Sheet for creating or editing a wage snapshot
struct WageSnapshotEditorSheet: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  let mode: PaySettingsViewModel.EditorMode
  let snapshot: WageSnapshot?
  let mostRecentSnapshot: WageSnapshot?
  /// User's currency from settings
  let userCurrency: String
  let onSave: (WageSnapshotEditorInput) async -> Bool
  let onDelete: (WageSnapshot) -> Void
  let onCancel: () -> Void

  // Form state
  @State private var fromDate = Date()  // swiftlint:disable:this explicit_type_interface
  @State private var usePreset: Bool = true
  @State private var wageLevel: Int = 1
  @State private var customWage: Double = 200
  @State private var supplements: [OnboardingSupplementRule] = []
  @State private var breakEnabled: Bool = true
  @State private var breakMethod: BreakMethod = .proportional
  @State private var breakThresholdHours: Double = 5.5
  @State private var breakDeductionMinutes: Int = 30
  @State private var taxEnabled: Bool = false
  @State private var taxPercentage: Double = 0

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
    mostRecentSnapshot: WageSnapshot?,
    userCurrency: String = "kr",
    onSave: @escaping (WageSnapshotEditorInput) async -> Bool,
    onDelete: @escaping (WageSnapshot) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.mode = mode
    self.snapshot = snapshot
    self.mostRecentSnapshot = mostRecentSnapshot
    self.userCurrency = userCurrency
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel

    // Tariff is only available for Norwegian krone
    let canUseTariff = userCurrency == "kr"

    // Initialize form state
    if mode == .edit, let snapshot {
      // Editing existing snapshot
      if let fromDateString = snapshot.from_date,
        let date = ISO8601DateFormatter.dateFromDateOnlyString(fromDateString)
      {
        _fromDate = State(initialValue: date)
      }
      // Only use preset if tariff is available AND snapshot uses tariff
      _usePreset = State(initialValue: canUseTariff && snapshot.wage_level != nil)
      _wageLevel = State(initialValue: snapshot.wage_level ?? 1)
      _customWage = State(initialValue: snapshot.hourly_wage)
      _supplements = State(
        initialValue: snapshot.supplements.rules.map { OnboardingSupplementRule(from: $0) })
      _breakEnabled = State(initialValue: snapshot.effectiveBreakEnabled)
      _breakMethod = State(initialValue: snapshot.breakMethod)
      _breakThresholdHours = State(initialValue: snapshot.effectiveBreakThresholdHours)
      _breakDeductionMinutes = State(initialValue: snapshot.effectiveBreakDeductionMinutes)
      _taxEnabled = State(initialValue: snapshot.effectiveTaxEnabled)
      _taxPercentage = State(initialValue: snapshot.effectiveTaxPercentage)
      // Initialize tariff type ID from snapshot
      _tariffTypeId = State(initialValue: snapshot.tariff_type_id)
    } else if let mostRecent = mostRecentSnapshot {
      // Creating new snapshot - prefill from most recent
      _fromDate = State(initialValue: Date())
      // Only use preset if tariff is available AND most recent uses tariff
      _usePreset = State(initialValue: canUseTariff && mostRecent.wage_level != nil)
      _wageLevel = State(initialValue: mostRecent.wage_level ?? 1)
      _customWage = State(initialValue: mostRecent.hourly_wage)
      _supplements = State(
        initialValue: mostRecent.supplements.rules.map { OnboardingSupplementRule(from: $0) })
      _breakEnabled = State(initialValue: mostRecent.effectiveBreakEnabled)
      _breakMethod = State(initialValue: mostRecent.breakMethod)
      _breakThresholdHours = State(initialValue: mostRecent.effectiveBreakThresholdHours)
      _breakDeductionMinutes = State(initialValue: mostRecent.effectiveBreakDeductionMinutes)
      _taxEnabled = State(initialValue: mostRecent.effectiveTaxEnabled)
      _taxPercentage = State(initialValue: mostRecent.effectiveTaxPercentage)
      // Initialize tariff type ID from most recent snapshot
      _tariffTypeId = State(initialValue: mostRecent.tariff_type_id)
    } else {
      // No existing snapshot - default to custom wage if tariff not available
      _usePreset = State(initialValue: canUseTariff)
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(spacing: Spacing.lg) {
            // Date section (or baseline indicator)
            dateSection

            Divider()
              .padding(.horizontal)

            // Wage source selector
            WageSourceSelector(
              usePreset: $usePreset,
              wageLevel: $wageLevel,
              customWage: $customWage,
              currency: currency,
              showTariffOption: showTariffOption,
              tariffVersion: tariffVersion,
              selectorFooterContent: showTariffOption && usePreset
                ? AnyView(tariffVersionIndicator)
                : nil
            )
            .padding(.horizontal)

            Divider()
              .padding(.horizontal)

            // Supplements section
            supplementsSection

            Divider()
              .padding(.horizontal)

            // Tax deduction section
            TaxDeductionSection(
              enabled: $taxEnabled,
              percentage: $taxPercentage
            )
            .padding(.horizontal)

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

            // Error message
            if let error = errorMessage {
              errorBanner(error)
                .padding(.horizontal)
            }
          }
          .padding(.vertical, Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if mode == .edit, !isBaseline {
            VStack(spacing: 0) {
              deleteButton
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.sm)
            }
            .frame(maxWidth: .infinity)
            .background(
              ZStack {
                Rectangle()
                  .fill(.ultraThinMaterial)
                LinearGradient(
                  colors: [Color.tidexBackground.opacity(0), Color.tidexBackground.opacity(0.92)],
                  startPoint: .top,
                  endPoint: .bottom
                )
              }
              .ignoresSafeArea(edges: .bottom)
              .allowsHitTesting(false)
            )
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
      .task {
        await loadTariffVersion()
      }
      .onChange(of: fromDate) { _, newDate in
        // Reload tariff version when date changes (for historical versions)
        Task { await loadTariffVersionForDate(newDate) }
      }
    }
  }

  // MARK: - Tariff Version Loading

  /// Load tariff version based on mode and date
  private func loadTariffVersion() async {
    guard showTariffOption else { return }

    isLoadingTariff = true
    defer { isLoadingTariff = false }

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

      let isoDate = ISO8601DateFormatter.dateOnlyString(from: fromDate)
      tariffVersion = try await TariffVersionService.shared.getTariffVersionForDate(
        tariffType: effectiveTariffTypeId,
        date: isoDate
      )

      logger.info("Loaded tariff version: \(tariffVersion?.effective_date ?? "none")")
    } catch {
      logger.error("Failed to load tariff version: \(error.localizedDescription)")
      // Fall back to static rates - tariffVersion remains nil
    }
  }

  /// Reload tariff version for a specific date (when date picker changes)
  private func loadTariffVersionForDate(_ date: Date) async {
    guard showTariffOption, let typeId = tariffTypeId else { return }

    isLoadingTariff = true
    defer { isLoadingTariff = false }

    let isoDate = ISO8601DateFormatter.dateOnlyString(from: date)

    do {
      tariffVersion = try await TariffVersionService.shared.getTariffVersionForDate(
        tariffType: typeId,
        date: isoDate
      )
      logger.info(
        "Reloaded tariff version for date \(isoDate): \(tariffVersion?.effective_date ?? "none")")
    } catch {
      logger.error("Failed to reload tariff version for date: \(error.localizedDescription)")
    }
  }

  // MARK: - Can Save

  private var canSave: Bool {
    if usePreset {
      return true  // Tariff always valid
    }
    return customWage > 0
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
                // Reload tariff version for the new type
                Task { await loadTariffVersionForSelectedType() }
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
    }
  }

  /// Format effective date for display
  private func formatEffectiveDate(_ isoDate: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    guard let date = dateFormatter.date(from: isoDate) else { return isoDate }

    let displayFormatter = DateFormatter()
    displayFormatter.dateFormat = "MMMM yyyy"
    return displayFormatter.string(from: date)
  }

  /// Reload tariff version when tariff type changes
  private func loadTariffVersionForSelectedType() async {
    guard showTariffOption, let typeId = tariffTypeId else { return }

    isLoadingTariff = true
    defer { isLoadingTariff = false }

    do {
      // Reset wage level when changing tariff type
      wageLevel = 1

      let isoDate = ISO8601DateFormatter.dateOnlyString(from: fromDate)
      tariffVersion = try await TariffVersionService.shared.getTariffVersionForDate(
        tariffType: typeId,
        date: isoDate
      )
      logger.info(
        "Loaded tariff version for type \(typeId): \(tariffVersion?.effective_date ?? "none")")
    } catch {
      logger.error(
        "Failed to load tariff version for type \(typeId): \(error.localizedDescription)")
    }
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
          Image(systemName: "star.fill")
            .foregroundColor(.tidexWarning)

          Text(.settingsPayEditorBaselineIndicator)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextPrimary)

          Spacer()
        }
        .padding(Spacing.sm)
        .background(Color.tidexWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))

        Text(.settingsPayEditorBaselineHelp)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      } else {
        // Date picker
        DatePicker(
          "",
          selection: $fromDate,
          displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .tint(.tidexBrandPrimary)
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

        Text(.settingsPayEditorFromDateHelp)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
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
          }
        }
      }

      if usePreset {
        // Read-only preset supplements (from tariff version or fallback)
        Text(.settingsPayEditorSupplementsTariff)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)

        let presetRules =
          tariffVersion?.supplements.rules ?? PayrollCalculator.presetSupplementRules
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

      // Delete button
      Button(action: {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
          supplements.removeAll { $0.id == rule.id }
        }
      }) {
        Image(systemName: "trash")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexError)
      }
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
    if let rate = rule.rate {
      return "+\(Int(rate)) kr/t"
    }
    if let percent = rule.percent {
      return "+\(Int(percent))%"
    }
    return ""
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
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
      .foregroundColor(.tidexTextOnDanger)
      .frame(maxWidth: .infinity)
      .frame(height: Spacing.buttonHeight)
      .background(Color.tidexError)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
  }

  // MARK: - Save

  private func save() async {
    isSaving = true
    errorMessage = nil

    // Build input - only use preset if tariff is available and selected
    let effectiveUsePreset = showTariffOption && usePreset

    // Resolve hourly wage: use tariff version rates if available, otherwise fallback
    let resolvedHourlyWage: Double
    if effectiveUsePreset {
      if let version = tariffVersion, let rate = version.rate(forLevel: wageLevel) {
        resolvedHourlyWage = rate
      } else {
        // Fallback to static preset rates
        resolvedHourlyWage = PayrollCalculator.presetWageRates[String(wageLevel)] ?? 184.54
      }
    } else {
      resolvedHourlyWage = customWage
    }

    let resolvedWageLevel = effectiveUsePreset ? wageLevel : nil

    // Resolve supplements: use tariff version supplements if available, otherwise fallback
    let resolvedSupplements: SupplementRulesSnapshot
    if effectiveUsePreset {
      if let version = tariffVersion {
        resolvedSupplements = version.supplements
      } else {
        // Fallback to static preset supplements
        resolvedSupplements = SupplementRulesSnapshot(
          rules: PayrollCalculator.presetSupplementRules)
      }
    } else {
      resolvedSupplements = SupplementRulesSnapshot(
        rules: supplements.map { $0.toSupplementRule() })
    }

    // Resolve tariff type ID: only set if using preset
    let resolvedTariffTypeId = effectiveUsePreset ? tariffTypeId : nil
    let resolvedBreakMethod: BreakMethod =
      breakEnabled && breakMethod == .none ? .proportional : breakMethod

    let input = WageSnapshotEditorInput(
      fromDate: isBaseline ? nil : fromDate,
      hourlyWage: resolvedHourlyWage,
      wageLevel: resolvedWageLevel,
      supplements: resolvedSupplements,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: resolvedBreakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes,
      tariffTypeId: resolvedTariffTypeId
    )

    let success = await onSave(input)

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

// MARK: - WageSnapshotEditorInput Extension

extension WageSnapshotEditorInput {
  /// Create input with explicit values (for editor sheet)
  init(
    fromDate: Date?,
    hourlyWage: Double,
    wageLevel: Int?,
    supplements: SupplementRulesSnapshot,
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
    mostRecentSnapshot: nil,
    onSave: { _ in true },
    onDelete: { _ in },
    onCancel: {}
  )
}
