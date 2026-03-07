import SwiftUI
import UIKit

// MARK: - Wage History Timeline View

/// Visual timeline displaying wage snapshots with change detection
struct WageHistoryTimelineView: View {
  let entries: [WageTimelineEntry]
  let currency: String
  let onAddNew: () -> Void
  let onEdit: (WageSnapshot) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header with add button
      HStack {
        Text(.settingsPayTimelineTitle)
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Button(action: {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          onAddNew()
        }) {
          Text(.settingsPayTimelineAddChange)
            .font(.tidexLabel)
            .foregroundColor(.tidexBlue)
            .lineLimit(1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxxs)
        }
        .buttonStyle(.plain)
        .tidexGlass(shape: .capsule, interactive: true)
        .accessibilityHint(Text(.settingsPayTimelineAddChangeHint))
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.md)

      if entries.isEmpty {
        // Empty state
        emptyState
          .padding(.bottom, Spacing.md)
      } else {
        // Timeline entries
        VStack(spacing: 0) {
          ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            TimelineEntryRow(
              entry: entry,
              currency: currency,
              isFirst: index == 0,
              isLast: index == entries.count - 1,
              hasFutureAbove: hasFutureAbove(at: index),
              wageChanged: didWageChange(at: index),
              shouldHighlightWage: shouldHighlightWage(at: index),
              onEdit: { onEdit(entry.snapshot) }
            )
          }
        }
        .padding(.bottom, Spacing.md)
      }
    }
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .tidexCardShadow(cornerRadius: CornerRadius.lg)
  }

  // MARK: - Empty State

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "clock.badge.questionmark")
        .font(.system(size: 32))
        .foregroundColor(.tidexTextMuted)

      Text(.settingsPayTimelineEmpty)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.xl)
    .padding(.horizontal, Spacing.md)
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
    guard let currentEntryIndex = entries.firstIndex(where: { $0.type == .current }) else {
      return false
    }
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
  @Environment(\.layoutDirection) private var layoutDirection
  let entry: WageTimelineEntry
  let currency: String
  let isFirst: Bool
  let isLast: Bool
  let hasFutureAbove: Bool
  let wageChanged: Bool
  let shouldHighlightWage: Bool
  let onEdit: () -> Void

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
        .padding(.leading, Spacing.md)

      // Content with vertical padding
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          // Title: wage rate or change description
          titleView

          // Date range
          Text(entry.dateRange)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        // Edit button
        Button(action: {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          onEdit()
        }) {
          Image(systemName: "pencil")
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextMuted)
            .padding(Spacing.xs)
        }
      }
      .padding(.vertical, verticalPadding)
      .padding(.trailing, Spacing.md)
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
    formatter.locale = Locale.appLocale
    let formatted = formatter.string(from: NSNumber(value: wage)) ?? "\(wage)"
    let currencyConfig = CurrencyConfig.get(currency)
    let perHour = String(localized: .commonPerHourShort)

    switch currencyConfig.display {
    case .prefix:
      return "\(currency)\(formatted)\(perHour)"
    case .suffix:
      return "\(formatted) \(currency)\(perHour)"
    }
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
    Text(formattedWage)
      .font(
        .system(
          size: entry.type == .current ? 24 : 16, weight: entry.type == .current ? .bold : .semibold
        )
      )
      .foregroundColor(shouldHighlightWage ? .tidexBlue : .tidexTextPrimary)
  }

  @ViewBuilder
  private var changesTitle: some View {
    VStack(alignment: .leading, spacing: Spacing.micro) {
      ForEach(nonWageChanges) { change in
        Text(rtlAdjustedChangeDescription(change.description))
          .font(
            .system(
              size: entry.type == .current ? 20 : 15,
              weight: entry.type == .current ? .bold : .semibold)
          )
          .foregroundColor(.tidexTextPrimary)
      }
    }
  }

  private func rtlAdjustedChangeDescription(_ description: String) -> String {
    guard layoutDirection == .rightToLeft else { return description }
    if let swapped = swapArrowValues(description, separator: " \u{2192} ", arrow: " \u{2190} ") {
      return swapped
    }
    if let swapped = swapArrowValues(description, separator: "\u{2192}", arrow: "\u{2190}") {
      return swapped
    }
    if let swapped = swapArrowValues(description, separator: " -> ", arrow: " <- ") {
      return swapped
    }
    if let swapped = swapArrowValues(description, separator: "->", arrow: "<-") { return swapped }
    return description
  }

  private func swapArrowValues(_ description: String, separator: String, arrow: String) -> String? {
    let parts = description.components(separatedBy: separator)
    guard parts.count == 2 else { return nil }
    let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = left.prefix { character in
      let scalar = character.unicodeScalars.first
      let isNumber = character.isNumber
      let isNumericSymbol =
        character == "%" || character == "." || character == "," || scalar?.value == 0x066B
        || scalar?.value == 0x066C
      return !(isNumber || isNumericSymbol)
    }
    let prefixString = String(prefix)
    let oldValue = left.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    let newValue = right
    let ordered = oldValue.isEmpty ? "\(right)\(arrow)\(left)" : "\(newValue)\(arrow)\(oldValue)"
    // Force the numeric/arrow sequence to render LTR within the RTL prefix.
    return "\(prefixString)\u{2066}\(ordered)\u{2069}"
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
        ),
      ],
      currency: "kr",
      onAddNew: {},
      onEdit: { _ in }
    )
    .padding()
  }
  .background(Color.tidexBackground)
}
