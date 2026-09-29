import SwiftUI
import UIKit

// MARK: - Applicable Supplements Helpers

/// Helper functions for filtering applicable supplements by time window
/// Ported from lib/payroll/applicable-supplements.ts
enum ApplicableSupplements {
  /// Get ALL supplement rules for a specific weekday (not filtered by time)
  /// Used to save non-visible rules alongside user edits
  static func getAllWeekdaySupplements(
    weekday: Int,
    rules: [SupplementRule]
  ) -> [CustomSupplementRuleWithId] {
    rules
      .filter { $0.days.contains(weekday) }
      .map { rule in
        CustomSupplementRuleWithId(
          from: rule.from,
          to: rule.to,
          rate: rule.rate,
          percent: rule.percent,
          isCustom: false
        )
      }
  }

  /// Get applicable supplement rules for a shift's time window
  ///
  /// Returns rules that overlap with the shift's time window.
  /// For cross-midnight shifts, this also checks rules for the next day.
  ///
  /// - Parameters:
  ///   - startTime: Shift start time (HH:MM)
  ///   - endTime: Shift end time (HH:MM)
  ///   - weekday: Weekday number (1-7, Mon-Sun) of the shift start date
  ///   - rules: Predefined supplement rules from snapshot
  /// - Returns: Rules that apply to this shift
  static func getApplicableSupplements(
    startTime: String,
    endTime: String,
    weekday: Int,
    rules: [SupplementRule]
  ) -> [CustomSupplementRuleWithId] {
    guard let (start, end) = WagePeriodBuilder.shiftMinutes(startTime: startTime, endTime: endTime)
    else {
      return []
    }
    // Clip weekday-specific rules to this occurrence before removing their weekday metadata.
    // Otherwise saving a Sunday all-day rule would also apply it to Saturday evening.
    let applicable = WagePeriodBuilder.ruleWindows(weekday: weekday, rules: rules)
      .filter { $0.to > start && $0.from < end }
      .map { window in
        CustomSupplementRuleWithId(
          from: clockTime(max(start, window.from), isEnd: false),
          to: clockTime(min(end, window.to), isEnd: true),
          rate: window.rule.rate,
          percent: window.rule.percent,
          isCustom: false
        )
      }
    var seen = Set<String>()
    return applicable.filter { rule in
      let key =
        "\(rule.from)-\(rule.to)-\(String(describing: rule.rate))-\(String(describing: rule.percent))"
      return seen.insert(key).inserted
    }
  }

  private static func clockTime(_ minutes: Int, isEnd: Bool) -> String {
    let normalized = (minutes % 1_440 + 1_440) % 1_440
    if isEnd, normalized == 0 { return "24:00" }
    return String(format: "%02d:%02d", normalized / 60, normalized % 60)
  }

  /// Shift-specific clock windows can overlap before or after midnight.
  static func filterToApplicable(
    rules: [CustomSupplementRuleWithId],
    startTime: String,
    endTime: String
  ) -> [CustomSupplementRuleWithId] {
    guard let (start, end) = WagePeriodBuilder.shiftMinutes(startTime: startTime, endTime: endTime)
    else {
      return []
    }
    return rules.filter { rule in
      WagePeriodBuilder.ruleWindows(
        weekday: 1,
        rules: [
          SupplementRule(
            days: Array(1...7), from: rule.from, to: rule.to,
            rate: rule.rate, percent: rule.percent)
        ]
      ).contains { $0.to > start && $0.from < end }
    }
  }

  /// Filter rules to those that do NOT overlap with shift time
  static func filterToNonApplicable(
    rules: [CustomSupplementRuleWithId],
    startTime: String,
    endTime: String
  ) -> [CustomSupplementRuleWithId] {
    let applicable = filterToApplicable(rules: rules, startTime: startTime, endTime: endTime)
    let applicableIds = Set(applicable.map(\.id))  // swiftlint:disable:this explicit_type_interface
    return rules.filter { !applicableIds.contains($0.id) }
  }
}

// MARK: - Custom Supplements Editor Sheet

/// Full-screen sheet for editing custom supplements on a shift
struct CustomSupplementsEditorSheet: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length type_body_length
  /// The shift being edited
  let shift: ShiftWithComputations
  /// User's currency for formatting
  let currency: String
  /// Tariff supplement rules from the applicable snapshot (filtered by weekday)
  let tariffRules: [SupplementRule]
  /// Callback when supplements are saved
  let onSave: (CustomSupplementsData?) -> Void
  /// Callback when editing is cancelled
  let onCancel: () -> Void

  @Environment(\.dismiss) private var dismiss

  /// Current list of supplement rules (with IDs for list management)
  @State private var rules: [CustomSupplementRuleWithId] = []

  /// Rules that don't overlap with the current shift time window
  /// These are preserved on save to handle future shift expansion
  @State private var nonApplicableRules: [CustomSupplementRuleWithId] = []

  /// Whether the shift originally had custom supplements
  @State private var hadCustomSupplements: Bool = false

  /// Currently editing rule (for sheet)
  @State private var editingRule: CustomSupplementRuleWithId?

  /// Whether showing add/edit rule sheet
  @State private var showingRuleEditor = false

  /// Whether the user has explicitly modified rules (added, edited, or deleted)
  @State private var userHasModifiedRules: Bool = false

  /// Whether delete confirmation is showing
  @State private var ruleToDelete: CustomSupplementRuleWithId?

  /// Haptic feedback
  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

  /// Get the weekday (1-7, Mon-Sun) from shift date
  private var shiftWeekday: Int {
    guard let date = Date.fromISODateString(shift.shiftDate) else { return 1 }
    let calendar = Calendar.gregorianCurrent
    // Calendar weekday is 1=Sunday, 2=Monday, etc.
    // We need 1=Monday, 7=Sunday
    let calendarWeekday = calendar.component(.weekday, from: date)
    return calendarWeekday == 1 ? 7 : calendarWeekday - 1
  }

  /// Whether any changes have been made
  private var hasChanges: Bool {
    // If we had custom supplements, always allow save (might be clearing or modifying)
    if hadCustomSupplements { return true }

    // If user explicitly modified rules (added, edited, or deleted), allow save
    if userHasModifiedRules { return true }

    // Otherwise, only if we have non-empty rules (tariff loaded, not yet modified)
    return !rules.isEmpty
  }

  var body: some View {
    NavigationStack {
      scrollContent
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .supplementsEditTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingRuleEditor) { ruleEditorSheet }
        .alert(
          String(localized: .supplementsDeleteRuleTitle),
          isPresented: .init(
            get: { ruleToDelete != nil },
            set: { if !$0 { ruleToDelete = nil } }
          )
        ) {
          Button(String(localized: .commonCancel), role: .cancel) {
            ruleToDelete = nil
          }
          Button(String(localized: .supplementsDeleteRule), role: .destructive) {
            if let rule = ruleToDelete {
              deleteRule(rule)
            }
            ruleToDelete = nil
          }
        } message: {
          Text(.supplementsDeleteRuleMessage)
        }
        .onAppear {
          initializeRules()
        }
    }
  }

  private var scrollContent: some View {
    ScrollView {
      VStack(spacing: Spacing.mlg) {
        // Info header
        infoHeader

        // Rules list
        if rules.isEmpty {
          emptyState
        } else {
          rulesList
        }

        // Add rule button
        addRuleButton

        // Reset to standard button (only if originally had custom supplements)
        if hadCustomSupplements {
          resetButton
        }

        Spacer()
          .frame(height: 100)
      }
      .padding(Spacing.mlg)
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button(String(localized: .commonCancel)) {
        onCancel()
      }
    }
    ToolbarItem(placement: .confirmationAction) {
      Button(String(localized: .commonSave)) {
        saveChanges()
      }
      .fontWeight(.semibold)
      .disabled(!hasChanges)
    }
  }

  private var ruleEditorSheet: some View {
    SupplementRuleEditorSheet(
      rule: editingRule,
      currency: currency,
      onSave: { updatedRule in
        handleRuleSaved(updatedRule)
        showingRuleEditor = false
      },
      onCancel: {
        showingRuleEditor = false
      }
    )
  }

  // MARK: - Initialization

  private func initializeRules() {
    // Check if shift has existing custom supplements (including explicitly empty rules)
    if let customSupplements = shift.shift.custom_supplements {
      // Load existing custom supplements
      hadCustomSupplements = true

      // Convert to rules with IDs
      let allCustomRules = customSupplements.rules.map { rule in
        CustomSupplementRuleWithId(from: rule)
      }

      // Filter to applicable and non-applicable
      rules = ApplicableSupplements.filterToApplicable(
        rules: allCustomRules,
        startTime: shift.startTime,
        endTime: shift.endTime
      )
      nonApplicableRules = ApplicableSupplements.filterToNonApplicable(
        rules: allCustomRules,
        startTime: shift.startTime,
        endTime: shift.endTime
      )
    } else {
      // No custom supplements - load applicable tariff rules
      hadCustomSupplements = false
      rules = ApplicableSupplements.getApplicableSupplements(
        startTime: shift.startTime,
        endTime: shift.endTime,
        weekday: shiftWeekday,
        rules: tariffRules
      )
      nonApplicableRules = []
    }
  }

  // MARK: - Views

  @ViewBuilder
  private var infoHeader: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "info.circle")
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)

      Text(.supplementsEditorHint)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      Spacer()
    }
    .padding(Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexBlue.opacity(0.08))
    )
  }

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "plus.circle.dashed")
        .font(.system(size: 40))
        .foregroundColor(.tidexTextMuted)

      Text(.supplementsNoRules)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Text(.supplementsNoRulesHint)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .multilineTextAlignment(.center)
    }
    .padding(.vertical, Spacing.xxl)
  }

  @ViewBuilder
  private var rulesList: some View {
    VStack(spacing: Spacing.sm) {
      ForEach(rules) { rule in
        ShiftSupplementRuleCard(
          rule: rule,
          currency: currency,
          onEdit: {
            impactHaptic.impactOccurred()
            editingRule = rule
            showingRuleEditor = true
          },
          onDelete: {
            impactHaptic.impactOccurred()
            ruleToDelete = rule
          }
        )
      }
    }
  }

  @ViewBuilder
  private var addRuleButton: some View {
    Button {
      impactHaptic.impactOccurred()
      editingRule = nil
      showingRuleEditor = true
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "plus.circle.fill")
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
        Text(.supplementsAddRule)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .stroke(Color.tidexBlue, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var resetButton: some View {
    Button {
      impactHaptic.impactOccurred()
      resetToStandard()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "arrow.counterclockwise")
          .font(.tidexSubheadline)
        Text(.supplementsResetToStandard)
          .font(.tidexLabel)
      }
      .foregroundColor(.tidexTextSecondary)
      .padding(.vertical, Spacing.sm)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Actions

  private func handleRuleSaved(_ rule: CustomSupplementRuleWithId) {
    if let index = rules.firstIndex(where: { $0.id == rule.id }) {
      // Update existing rule
      rules[index] = rule
    } else {
      // Add new rule
      rules.append(rule)
    }
    userHasModifiedRules = true
    editingRule = nil
  }

  private func deleteRule(_ rule: CustomSupplementRuleWithId) {
    rules.removeAll { $0.id == rule.id }
    userHasModifiedRules = true
  }

  private func resetToStandard() {
    // Clear custom supplements - will return nil on save
    rules = ApplicableSupplements.getApplicableSupplements(
      startTime: shift.startTime,
      endTime: shift.endTime,
      weekday: shiftWeekday,
      rules: tariffRules
    )
    nonApplicableRules = []
    hadCustomSupplements = false  // Treat as if we never had custom supplements
    userHasModifiedRules = false
  }

  private func saveChanges() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)

    // If all rules were explicitly removed, save empty object to mean "no supplements"
    // (distinct from nil which means "use tariff defaults")
    if rules.isEmpty, nonApplicableRules.isEmpty, hadCustomSupplements || userHasModifiedRules {
      onSave(CustomSupplementsData(rules: []))
      return
    }

    // If no rules and no explicit modification, return nil (use tariff)
    if rules.isEmpty, !hadCustomSupplements {
      onSave(nil)
      return
    }

    // If all rules are non-custom (tariff) and unchanged from original tariff, return nil
    if !hadCustomSupplements, rules.allSatisfy({ !$0.isCustom }) {
      // Check if rules match exactly what we'd get from tariff
      let tariffApplicable = ApplicableSupplements.getApplicableSupplements(
        startTime: shift.startTime,
        endTime: shift.endTime,
        weekday: shiftWeekday,
        rules: tariffRules
      )
      if rulesMatch(rules, tariffApplicable) {
        onSave(nil)
        return
      }
    }

    // Merge visible rules with non-applicable rules
    let allRules: [CustomSupplementRule] =
      rules.map { $0.toCustomSupplementRule() }
      + nonApplicableRules.map { $0.toCustomSupplementRule() }

    // If all rules were deleted, return empty rules to indicate "no supplements"
    // (Different from nil which means "use tariff")
    let customSupplements = CustomSupplementsData(rules: allRules)
    onSave(customSupplements)
  }

  private func rulesMatch(_ a: [CustomSupplementRuleWithId], _ b: [CustomSupplementRuleWithId])
    -> Bool
  {
    guard a.count == b.count else { return false }

    let sortedA = a.sorted { "\($0.from)-\($0.to)" < "\($1.from)-\($1.to)" }
    let sortedB = b.sorted { "\($0.from)-\($0.to)" < "\($1.from)-\($1.to)" }

    for (ruleA, ruleB) in zip(sortedA, sortedB) {
      if ruleA.from != ruleB.from || ruleA.to != ruleB.to || ruleA.rate != ruleB.rate
        || ruleA.percent != ruleB.percent
      {
        return false
      }
    }
    return true
  }
}

// MARK: - Preview

#Preview("Editor - No Custom") {
  CustomSupplementsEditorSheet(
    shift: ShiftWithComputations(
      shift: ShiftRow(
        id: "preview-1",
        user_id: "user-1",
        shift_date: "2025-01-17",
        start_time: "17:00",
        end_time: "23:00",
        custom_supplements: nil
      ),
      computed: ShiftComputed(
        id: "preview-1",
        durationHours: 6.0,
        paidHours: 5.5,
        basePay: 1_100,
        supplementPay: 90,
        gross: 1_190,
        wagePeriods: [],
        originalWagePeriods: [],
        breakAudit: BreakAudit(
          method: .proportional, thresholdHours: 5.5, deductedHours: 0.5, notes: [])
      ),
      taxEnabled: false,
      taxPercentage: 0
    ),
    currency: "kr",
    tariffRules: [
      SupplementRule(days: [1, 2, 3, 4, 5], from: "21:00", to: "06:00", rate: 45),
      SupplementRule(days: [6, 7], from: "00:00", to: "24:00", rate: 55),
    ],
    onSave: { _ in },
    onCancel: {}
  )
}

#Preview("Editor - With Custom") {
  CustomSupplementsEditorSheet(
    shift: ShiftWithComputations(
      shift: ShiftRow(
        id: "preview-2",
        user_id: "user-1",
        shift_date: "2025-01-17",
        start_time: "17:00",
        end_time: "23:00",
        custom_supplements: CustomSupplementsData(rules: [
          CustomSupplementRule(from: "21:00", to: "23:00", rate: 60, percent: nil, isCustom: true)
        ])
      ),
      computed: ShiftComputed(
        id: "preview-2",
        durationHours: 6.0,
        paidHours: 5.5,
        basePay: 1_100,
        supplementPay: 120,
        gross: 1_220,
        wagePeriods: [],
        originalWagePeriods: [],
        breakAudit: BreakAudit(
          method: .proportional, thresholdHours: 5.5, deductedHours: 0.5, notes: [])
      ),
      taxEnabled: false,
      taxPercentage: 0
    ),
    currency: "kr",
    tariffRules: [
      SupplementRule(days: [1, 2, 3, 4, 5], from: "21:00", to: "06:00", rate: 45)
    ],
    onSave: { _ in },
    onCancel: {}
  )
}  // swiftlint:disable:this file_length
