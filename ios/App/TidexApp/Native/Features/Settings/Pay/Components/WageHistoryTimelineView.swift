import SwiftUI
import UIKit

// MARK: - Wage History Timeline View

/// Visual timeline displaying wage snapshots with change detection
struct WageHistoryTimelineView: View {
    let entries: [WageTimelineEntry]
    let onAddNew: () -> Void
    let onEdit: (WageSnapshot) -> Void

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with add button
            HStack {
                Text(localization.string("settings.pay.timeline.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onAddNew()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))

                        Text(localization.string("settings.pay.timeline.addNew"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.tidexBlue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            if entries.isEmpty {
                // Empty state
                emptyState
                    .padding(.bottom, 16)
            } else {
                // Timeline entries
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TimelineEntryRow(
                            entry: entry,
                            isFirst: index == 0,
                            isLast: index == entries.count - 1,
                            hasFutureAbove: hasFutureAbove(at: index),
                            wageChanged: didWageChange(at: index),
                            shouldHighlightWage: shouldHighlightWage(at: index),
                            onEdit: { onEdit(entry.snapshot) }
                        )
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(.tidexTextMuted)

            Text(localization.string("settings.pay.timeline.empty"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func hasFutureAbove(at index: Int) -> Bool {
        guard index > 0 else { return false }
        return entries[index - 1].type == .future
    }

    /// Check if the entry at this index changed the wage from the previous (older) entry
    private func didWageChange(at index: Int) -> Bool {
        guard index < entries.count - 1 else { return false }
        let currentWage = entries[index].snapshot.hourly_wage
        let previousWage = entries[index + 1].snapshot.hourly_wage
        return currentWage != previousWage
    }

    /// Check if this past entry should have its wage highlighted in blue
    /// This happens when it introduced the current wage, but the current entry only changed settings
    private func shouldHighlightWage(at index: Int) -> Bool {
        let entry = entries[index]

        // Only highlight past entries (not future or current)
        guard entry.type == .past else { return false }

        // Find the current entry and its wage
        guard let currentEntryIndex = entries.firstIndex(where: { $0.type == .current }) else { return false }
        let currentEntry = entries[currentEntryIndex]
        let currentWage = currentEntry.snapshot.hourly_wage

        // Check if the current entry changed the wage
        let currentEntryChangedWage = didWageChange(at: currentEntryIndex)

        // If current entry changed the wage, no past entry should be highlighted
        if currentEntryChangedWage { return false }

        // This entry should be highlighted if it introduced the current wage
        // (it has the current wage, but the entry after it (older) doesn't)
        if entry.snapshot.hourly_wage != currentWage { return false }

        // Check if the next entry (older) has a different wage
        if index < entries.count - 1 {
            let olderWage = entries[index + 1].snapshot.hourly_wage
            return olderWage != currentWage
        }

        // This is the oldest entry with the current wage
        return true
    }
}

// MARK: - Timeline Entry Row

private struct TimelineEntryRow: View {
    let entry: WageTimelineEntry
    let isFirst: Bool
    let isLast: Bool
    let hasFutureAbove: Bool
    let wageChanged: Bool
    let shouldHighlightWage: Bool
    let onEdit: () -> Void

    @Environment(\.localization) private var localization

    /// Non-wage changes (excludes wage changes from the list)
    private var nonWageChanges: [WageChange] {
        entry.changes.filter { $0.type != .wage }
    }

    private var verticalPadding: CGFloat {
        entry.type == .current ? 16 : 10
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Timeline indicator (dot and lines) - no vertical padding
            timelineIndicator
                .frame(width: 40)
                .padding(.leading, 16)

            // Content with vertical padding
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Title: wage rate or change description
                    titleView

                    // Date range
                    Text(entry.dateRange)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                }

                Spacer()

                // Edit button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEdit()
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextMuted)
                        .padding(8)
                }
            }
            .padding(.vertical, verticalPadding)
            .padding(.trailing, 16)
        }
        .background(
            entry.type == .current
                ? Color.tidexBrandPrimary.opacity(0.08)
                : Color.clear
        )
    }

    // MARK: - Timeline Indicator

    @ViewBuilder
    private var timelineIndicator: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2

            ZStack {
                // Top line - from very top to center
                if !isFirst {
                    topLineView
                        .frame(width: 2, height: centerY)
                        .position(x: centerX, y: centerY / 2)
                }

                // Bottom line - from center to very bottom
                if !isLast {
                    bottomLineView
                        .frame(width: 2, height: centerY)
                        .position(x: centerX, y: centerY + centerY / 2)
                }

                // Dot centered
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: centerX, y: centerY)
            }
        }
    }

    private var dotSize: CGFloat {
        entry.type == .current ? 14 : 8
    }

    private var dotColor: Color {
        switch entry.type {
        case .future:
            return .tidexTextMuted
        case .current:
            return .tidexBrandPrimary
        case .past:
            return .tidexBrandPrimary.opacity(0.6)
        }
    }

    @ViewBuilder
    private var topLineView: some View {
        if entry.type == .future || hasFutureAbove {
            DashedLineRect(color: .tidexBorder)
        } else {
            Rectangle()
                .fill(Color.tidexBrandPrimary.opacity(0.3))
        }
    }

    @ViewBuilder
    private var bottomLineView: some View {
        if entry.type == .future {
            DashedLineRect(color: .tidexBorder)
        } else {
            Rectangle()
                .fill(Color.tidexBrandPrimary.opacity(0.3))
        }
    }

    // MARK: - Title View

    private var formattedWage: String {
        let wage = entry.snapshot.hourly_wage
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "nb_NO")
        return formatter.string(from: NSNumber(value: wage)) ?? "\(wage)"
    }

    /// Determine what to show as the title
    /// - If wage changed or should be highlighted: show wage (blue if highlighted)
    /// - If only settings changed: show the changes as title
    /// - Fallback: show wage (baseline or first entry)
    @ViewBuilder
    private var titleView: some View {
        if wageChanged || shouldHighlightWage || nonWageChanges.isEmpty {
            // Show wage as title
            wageTitle
        } else {
            // Show changes as title (settings changed but not wage)
            changesTitle
        }
    }

    @ViewBuilder
    private var wageTitle: some View {
        Text("\(formattedWage) kr/t")
            .font(.system(size: entry.type == .current ? 24 : 16, weight: entry.type == .current ? .bold : .semibold))
            .foregroundColor(shouldHighlightWage ? .tidexBlue : .tidexTextPrimary)
    }

    @ViewBuilder
    private var changesTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(nonWageChanges) { change in
                Text(change.description)
                    .font(.system(size: entry.type == .current ? 20 : 15, weight: entry.type == .current ? .bold : .semibold))
                    .foregroundColor(.tidexTextPrimary)
            }
        }
    }
}

// MARK: - Dashed Line

private struct DashedLineRect: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: geometry.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        WageHistoryTimelineView(
            entries: [
                WageTimelineEntry(
                    id: "1",
                    snapshot: WageSnapshot(
                        id: "1",
                        user_id: "test",
                        from_date: "2025-02-01",
                        hourly_wage: 195.0,
                        wage_level: 2,
                        tariff_type_id: nil,
                        supplements: SupplementRulesSnapshot(rules: []),
                        tax_enabled: nil,
                        tax_percentage: nil,
                        break_enabled: nil,
                        break_method: nil,
                        break_threshold_hours: nil,
                        break_deduction_minutes: nil,
                        created_at: nil
                    ),
                    type: .future,
                    dateRange: "1. Feb 2025 -",
                    endDate: nil,
                    changes: []
                ),
                WageTimelineEntry(
                    id: "2",
                    snapshot: WageSnapshot(
                        id: "2",
                        user_id: "test",
                        from_date: "2024-06-01",
                        hourly_wage: 184.54,
                        wage_level: 1,
                        tariff_type_id: nil,
                        supplements: SupplementRulesSnapshot(rules: []),
                        tax_enabled: nil,
                        tax_percentage: nil,
                        break_enabled: nil,
                        break_method: nil,
                        break_threshold_hours: nil,
                        break_deduction_minutes: nil,
                        created_at: nil
                    ),
                    type: .current,
                    dateRange: "1. Jun 2024 - na",
                    endDate: nil,
                    changes: [
                        WageChange(description: "180,00 -> 184,54 kr/t", type: .wage)
                    ]
                ),
                WageTimelineEntry(
                    id: "3",
                    snapshot: WageSnapshot(
                        id: "3",
                        user_id: "test",
                        from_date: nil,
                        hourly_wage: 180.0,
                        wage_level: 1,
                        tariff_type_id: nil,
                        supplements: SupplementRulesSnapshot(rules: []),
                        tax_enabled: nil,
                        tax_percentage: nil,
                        break_enabled: nil,
                        break_method: nil,
                        break_threshold_hours: nil,
                        break_deduction_minutes: nil,
                        created_at: nil
                    ),
                    type: .past,
                    dateRange: "Standard (grunnlinje)",
                    endDate: nil,
                    changes: []
                )
            ],
            onAddNew: {},
            onEdit: { _ in }
        )
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
