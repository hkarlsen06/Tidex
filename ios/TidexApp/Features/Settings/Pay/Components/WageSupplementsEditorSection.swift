import SwiftUI

/// Supplement rules for a wage snapshot. Tariff rules are read-only. Custom rules can be
/// added, edited and deleted.
struct SupplementsEditorSection: View {
  let usePreset: Bool
  let presetRules: [SupplementRule]
  @Binding var supplements: [OnboardingSupplementRule]
  let currency: String
  let onAdd: () -> Void
  let onEdit: (OnboardingSupplementRule) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        Text(.settingsPayEditorSupplementsTitle)
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        if !usePreset {
          Button(action: onAdd) {
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

        ForEach(presetRules.indices, id: \.self) { index in
          presetSupplementRow(presetRules[index])
        }
      } else {
        // Editable custom supplements
        customSupplements
      }
    }
    .padding(.horizontal)
    .sensoryFeedback(.impact(weight: .light), trigger: supplements.count)
  }

  @ViewBuilder
  private var customSupplements: some View {
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

      editButton(for: rule)

      deleteButton(for: rule)
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
  }

  private func editButton(for rule: OnboardingSupplementRule) -> some View {
    Button(action: {
      onEdit(rule)
    }) {
      Image(systemName: "pencil")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .accessibilityLabel(
      Text(.supplementsEditRuleAccessibility("\(rule.daysDescription), \(rule.timeDescription)")))
  }

  private func deleteButton(for rule: OnboardingSupplementRule) -> some View {
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
}
