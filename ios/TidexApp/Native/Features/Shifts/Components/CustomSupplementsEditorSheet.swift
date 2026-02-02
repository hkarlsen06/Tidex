import SwiftUI
import UIKit

// MARK: - Applicable Supplements Helpers

/// Helper functions for filtering applicable supplements by time window
/// Ported from lib/payroll/applicable-supplements.ts
enum ApplicableSupplements {
    /// Get next weekday (1-7 Mon-Sun, wraps around)
    private static func getNextWeekday(_ weekday: Int) -> Int {
        weekday == 7 ? 1 : weekday + 1
    }

    /// Convert HH:MM time string to minutes from midnight
    private static func toMinutes(_ hhmm: String) -> Int {
        let components = hhmm.prefix(5).split(separator: ":")
        guard components.count == 2,
              let h = Int(components[0]),
              let m = Int(components[1]) else {
            return 0
        }
        return h * 60 + m
    }

    /// Check if two time ranges overlap
    private static func rangesOverlap(
        shiftStart: Int,
        shiftEnd: Int,
        ruleFrom: Int,
        ruleTo: Int
    ) -> Bool {
        // Ranges overlap if neither ends before the other starts
        shiftStart < ruleTo && ruleFrom < shiftEnd
    }

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
        let shiftStart = toMinutes(startTime)
        var shiftEnd = toMinutes(endTime)

        // Handle cross-midnight shifts
        let isCrossMidnight = shiftEnd <= shiftStart
        if isCrossMidnight {
            shiftEnd += 24 * 60  // Add 24 hours
        }

        var applicable: [CustomSupplementRuleWithId] = []
        let nextWeekday = getNextWeekday(weekday)

        for rule in rules {
            let appliesToStartDay = rule.days.contains(weekday)
            let appliesToNextDay = rule.days.contains(nextWeekday)

            // Skip rules that don't apply to either relevant day
            guard appliesToStartDay || appliesToNextDay else { continue }

            let ruleFrom = toMinutes(rule.from)
            var ruleTo = toMinutes(rule.to)

            // Handle cross-midnight rules
            if ruleTo < ruleFrom {
                ruleTo += 24 * 60
            }

            // Check overlap with start day
            if appliesToStartDay && rangesOverlap(
                shiftStart: shiftStart,
                shiftEnd: shiftEnd,
                ruleFrom: ruleFrom,
                ruleTo: ruleTo
            ) {
                applicable.append(CustomSupplementRuleWithId(
                    from: rule.from,
                    to: rule.to,
                    rate: rule.rate,
                    percent: rule.percent,
                    isCustom: false
                ))
                continue
            }

            // For cross-midnight shifts, check if next-day rules apply
            if isCrossMidnight && appliesToNextDay {
                let nextDayRuleFrom = ruleFrom + 24 * 60
                let nextDayRuleTo = ruleTo + 24 * 60
                if rangesOverlap(
                    shiftStart: shiftStart,
                    shiftEnd: shiftEnd,
                    ruleFrom: nextDayRuleFrom,
                    ruleTo: nextDayRuleTo
                ) {
                    applicable.append(CustomSupplementRuleWithId(
                        from: rule.from,
                        to: rule.to,
                        rate: rule.rate,
                        percent: rule.percent,
                        isCustom: false
                    ))
                }
            }
        }

        // Remove duplicates
        var seen = Set<String>()
        return applicable.filter { rule in
            let key = "\(rule.from)-\(rule.to)-\(rule.rate ?? 0)-\(rule.percent ?? 0)"
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    /// Filter custom supplement rules to only those that overlap with shift time
    static func filterToApplicable(
        rules: [CustomSupplementRuleWithId],
        startTime: String,
        endTime: String
    ) -> [CustomSupplementRuleWithId] {
        let shiftStart = toMinutes(startTime)
        var shiftEnd = toMinutes(endTime)

        // Handle cross-midnight shifts
        if shiftEnd <= shiftStart {
            shiftEnd += 24 * 60
        }

        return rules.filter { rule in
            let ruleFrom = toMinutes(rule.from)
            var ruleTo = toMinutes(rule.to)

            // Handle cross-midnight rules
            if ruleTo < ruleFrom {
                ruleTo += 24 * 60
            }

            return rangesOverlap(
                shiftStart: shiftStart,
                shiftEnd: shiftEnd,
                ruleFrom: ruleFrom,
                ruleTo: ruleTo
            )
        }
    }

    /// Filter rules to those that do NOT overlap with shift time
    static func filterToNonApplicable(
        rules: [CustomSupplementRuleWithId],
        startTime: String,
        endTime: String
    ) -> [CustomSupplementRuleWithId] {
        let applicable = filterToApplicable(rules: rules, startTime: startTime, endTime: endTime)
        let applicableIds = Set(applicable.map { $0.id })
        return rules.filter { !applicableIds.contains($0.id) }
    }
}

// MARK: - Custom Supplements Editor Sheet

/// Full-screen sheet for editing custom supplements on a shift
struct CustomSupplementsEditorSheet: View {
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

    /// Whether delete confirmation is showing
    @State private var ruleToDelete: CustomSupplementRuleWithId?

    /// Haptic feedback
    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

    /// Get the weekday (1-7, Mon-Sun) from shift date
    private var shiftWeekday: Int {
        guard let date = Date.fromISODateString(shift.shiftDate) else { return 1 }
        let calendar = Calendar.current
        // Calendar weekday is 1=Sunday, 2=Monday, etc.
        // We need 1=Monday, 7=Sunday
        let calendarWeekday = calendar.component(.weekday, from: date)
        return calendarWeekday == 1 ? 7 : calendarWeekday - 1
    }

    /// Whether any changes have been made
    private var hasChanges: Bool {
        // If we didn't have custom supplements and still don't have visible rules, no change
        if !hadCustomSupplements && rules.isEmpty { return false }

        // If we had custom supplements, always allow save (might be clearing or modifying)
        if hadCustomSupplements { return true }

        // Otherwise, we have new rules
        return !rules.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                .padding(20)
            }
            .background(Color.tidexBackground)
            .navigationTitle(String(localized: .supplementsEditTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .sheet(isPresented: $showingRuleEditor) {
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

    // MARK: - Initialization

    private func initializeRules() {
        // Check if shift has existing custom supplements
        if let customSupplements = shift.shift.custom_supplements,
           !customSupplements.rules.isEmpty {
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
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundColor(.tidexBlue)

            Text(.supplementsEditorHint)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexBlue.opacity(0.08))
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 40))
                .foregroundColor(.tidexTextMuted)

            Text(.supplementsNoRules)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            Text(.supplementsNoRulesHint)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var rulesList: some View {
        VStack(spacing: 12) {
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
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                Text(.supplementsAddRule)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.tidexBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 12)
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
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
                Text(.supplementsResetToStandard)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.tidexTextSecondary)
            .padding(.vertical, 12)
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
        editingRule = nil
    }

    private func deleteRule(_ rule: CustomSupplementRuleWithId) {
        rules.removeAll { $0.id == rule.id }
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
    }

    private func saveChanges() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // If no rules and we're resetting, return nil to clear custom supplements
        if rules.isEmpty && !hadCustomSupplements {
            onSave(nil)
            return
        }

        // If all rules are non-custom (tariff) and unchanged from original tariff, return nil
        if !hadCustomSupplements && rules.allSatisfy({ !$0.isCustom }) {
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
        let allRules: [CustomSupplementRule] = rules.map { $0.toCustomSupplementRule() }
            + nonApplicableRules.map { $0.toCustomSupplementRule() }

        // If all rules were deleted, return empty rules to indicate "no supplements"
        // (Different from nil which means "use tariff")
        let customSupplements = CustomSupplementsData(rules: allRules)
        onSave(customSupplements)
    }

    private func rulesMatch(_ a: [CustomSupplementRuleWithId], _ b: [CustomSupplementRuleWithId]) -> Bool {
        guard a.count == b.count else { return false }

        let sortedA = a.sorted { "\($0.from)-\($0.to)" < "\($1.from)-\($1.to)" }
        let sortedB = b.sorted { "\($0.from)-\($0.to)" < "\($1.from)-\($1.to)" }

        for (ruleA, ruleB) in zip(sortedA, sortedB) {
            if ruleA.from != ruleB.from ||
               ruleA.to != ruleB.to ||
               ruleA.rate != ruleB.rate ||
               ruleA.percent != ruleB.percent {
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
                basePay: 1100,
                supplementPay: 90,
                gross: 1190,
                wagePeriods: [],
                originalWagePeriods: [],
                breakAudit: BreakAudit(method: .proportional, thresholdHours: 5.5, deductedHours: 0.5, notes: [])
            ),
            taxEnabled: false,
            taxPercentage: 0
        ),
        currency: "kr",
        tariffRules: [
            SupplementRule(days: [1, 2, 3, 4, 5], from: "21:00", to: "06:00", rate: 45),
            SupplementRule(days: [6, 7], from: "00:00", to: "24:00", rate: 55)
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
                basePay: 1100,
                supplementPay: 120,
                gross: 1220,
                wagePeriods: [],
                originalWagePeriods: [],
                breakAudit: BreakAudit(method: .proportional, thresholdHours: 5.5, deductedHours: 0.5, notes: [])
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
}
