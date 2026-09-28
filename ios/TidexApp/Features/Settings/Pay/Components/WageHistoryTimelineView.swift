import SwiftUI

// MARK: - Wage History Timeline View

/// Visual timeline displaying wage snapshots with change detection
struct WageHistoryTimelineView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let entries: [WageTimelineEntry]
  let currency: String
  let onAddNew: () -> Void
  let onEdit: (WageSnapshot) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header with add button
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Spacing.sm) {
          title
          Spacer(minLength: Spacing.xs)
          addChangeButton
        }
        VStack(alignment: .leading, spacing: Spacing.xs) {
          title
          addChangeButton
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)

      if entries.isEmpty {
        emptyState
          .padding(.bottom, Spacing.md)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            TimelineEntryRow(
              entry: entry,
              currency: currency,
              isFirst: index == 0,
              isLast: index == entries.count - 1,
              hasFutureAbove: hasFutureAbove(at: index),
              onEdit: { onEdit(entry.snapshot) }
            )
          }
        }
        .padding(.bottom, Spacing.md)
      }
    }
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
  }

  private var title: some View {
    Text(.settingsPayTimelineTitle)
      .font(.tidexTitle2)
      .foregroundColor(.tidexTextPrimary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }

  private var addChangeButton: some View {
    Button(action: {
      Haptics.play(.light)
      onAddNew()
    }) {
      Label(.settingsPayTimelineAddChange, systemImage: "plus")
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlue)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.tidexBlue.opacity(0.12), in: Capsule())
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("pay-history.add-change")
    .accessibilityHint(Text(.settingsPayTimelineAddChangeHint))
  }

  // MARK: - Empty State

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "clock.badge.questionmark")
        .font(.tidexAmountLarge)
        .foregroundColor(.tidexTextMuted)
        .accessibilityHidden(true)

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

}

// MARK: - Timeline Entry Row

private struct TimelineEntryRow: View {
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let entry: WageTimelineEntry
  let currency: String
  let isFirst: Bool
  let isLast: Bool
  let hasFutureAbove: Bool
  let onEdit: () -> Void

  /// Non-wage changes (excludes wage changes from the list)
  private var nonWageChanges: [WageChange] {
    entry.changes.filter { $0.type != .wage }
  }

  private var verticalPadding: CGFloat {
    entry.type == .current ? Spacing.md : Spacing.sm
  }

  var body: some View {
    Button {
      Haptics.play(.light)
      onEdit()
    } label: {
      HStack(alignment: .center, spacing: 0) {
        // Timeline indicator (dot and lines) - no vertical padding
        timelineIndicator
          .frame(width: Spacing.lg)
          .padding(.leading, Spacing.md)
          .padding(.trailing, Spacing.xs)
          .accessibilityHidden(true)

        content
          .padding(.vertical, verticalPadding)
          .padding(.trailing, Spacing.md)
      }
      .background(
        entry.type == .current
          ? Color.tidexBrandPrimary.opacity(0.08)
          : Color.clear
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(.settingsPayTimelineEditPeriod(entry.dateRange)))
    .accessibilityValue(
      ([String(localized: statusTitle), formattedWage] + nonWageChanges.map(\.description))
        .joined(separator: ", ")
    )
    .accessibilityIdentifier("pay-history.period.\(entry.id)")
  }

  private var content: some View {
    HStack(spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        if dynamicTypeSize.isAccessibilitySize {
          dateText
          wageTitle
        } else {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            dateText
            Spacer(minLength: Spacing.xs)
            wageTitle
          }
        }

        changesText
      }

      Image(systemName: "chevron.right")
        .font(.tidexCaption)
        .foregroundColor(.tidexTextMuted)
        .accessibilityHidden(true)
    }
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
      return .tidexTextMuted
    }
  }

  @ViewBuilder
  private var topLineView: some View {
    if entry.type == .future || hasFutureAbove {
      DashedLineRect(color: .tidexBorder)
    } else {
      Rectangle()
        .fill(Color.tidexBorder)
    }
  }

  @ViewBuilder
  private var bottomLineView: some View {
    if entry.type == .future {
      DashedLineRect(color: .tidexBorder)
    } else {
      Rectangle()
        .fill(Color.tidexBorder)
    }
  }

  // MARK: - Title View

  private var formattedWage: String {
    let wage = entry.snapshot.hourly_wage
    let formatted = CurrencyConfig.formatPlain(wage, includeDecimals: true)
    let currencyConfig = CurrencyConfig.get(currency)
    let perHour = String(localized: .commonPerHourShort)

    switch currencyConfig.display {
    case .prefix:
      return "\(currency)\(formatted)\(perHour)"

    case .suffix:
      return "\(formatted) \(currency)\(perHour)"
    }
  }

  private var statusTitle: LocalizedStringResource {
    switch entry.type {
    case .current:
      return .settingsPayTimelineCurrent
    case .future:
      return .settingsPayTimelineScheduled
    case .past:
      return .settingsPayTimelinePrevious
    }
  }

  private var dateText: some View {
    Text(entry.dateRange)
      .font(.tidexLabel)
      .foregroundColor(entry.type == .past ? .tidexTextSecondary : .tidexTextPrimary)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
      .minimumScaleFactor(0.8)
  }

  private var wageTitle: some View {
    Text(formattedWage)
      .font(entry.type == .current ? .tidexTitle : .tidexBodyMedium)
      .foregroundColor(.tidexTextPrimary)
      .monospacedDigit()
      .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
  }

  /// All non-wage changes in one line under the date and wage. The edit sheet shows the full list.
  @ViewBuilder
  private var changesText: some View {
    if !nonWageChanges.isEmpty {
      Text(nonWageChanges.map { rtlAdjustedChangeDescription($0.description) }.joined(separator: " · "))
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
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
      .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
