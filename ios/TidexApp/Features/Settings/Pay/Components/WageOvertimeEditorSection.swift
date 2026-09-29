import SwiftUI

/// Overtime toggle with the weekly threshold and the editable rule list.
struct OvertimeEditorSection: View {
  @Binding var enabled: Bool
  @Binding var thresholdHours: Double
  @Binding var rules: [OvertimeRuleDraft]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Toggle(isOn: $enabled) {
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

      if enabled {
        thresholdField

        ForEach($rules) { $rule in
          OvertimeRuleRow(rule: $rule) {
            rules.removeAll { $0.id == rule.id }
          }
        }

        addRuleButton
      }
    }
    .padding(.horizontal)
  }

  private var thresholdField: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayEditorOvertimeThreshold)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      TextField(
        "",
        value: $thresholdHours,
        format: .number.precision(.fractionLength(0...2))
      )
      .keyboardType(.decimalPad)
      .textFieldStyle(.roundedBorder)
      .accessibilityLabel(Text(.settingsPayEditorOvertimeThreshold))
    }
  }

  private var addRuleButton: some View {
    Button {
      rules.append(
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

private struct OvertimeRuleRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var rule: OvertimeRuleDraft
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      dayButtons

      Toggle(isOn: $rule.appliesOnHolidays) {
        Text(.settingsPayEditorOvertimeHolidayToggle)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
      .tint(.tidexBrandPrimary)

      timeFields
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
  }

  private var dayButtons: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.xs) {
        ForEach(1...7, id: \.self) { day in
          dayButton(day)
        }
      }

      // Names that no longer fit on one line wrap to a grid of larger targets.
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 72), spacing: Spacing.xs)],
        alignment: .leading,
        spacing: Spacing.xs
      ) {
        ForEach(1...7, id: \.self) { day in
          dayButton(day)
        }
      }
    }
  }

  private func dayButton(_ day: Int) -> some View {
    let isSelected = rule.days.contains(day)
    return Button {
      if isSelected {
        rule.days.remove(day)
      } else {
        rule.days.insert(day)
      }
    } label: {
      HStack(spacing: Spacing.micro) {
        if isSelected {
          Image(systemName: "checkmark")
            .font(.tidexMicro.weight(.bold))
            .accessibilityHidden(true)
        }
        Text(dayShortName(day))
          .font(.tidexCaption)
      }
      .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexTextSecondary)
      .frame(minWidth: 30, minHeight: 28)
      .padding(.horizontal, Spacing.micro)
      .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
          .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
      )
      // The chip stays compact. The tap area reaches 44pt.
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var timeFieldsLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.xs))
  }

  private var timeFields: some View {
    timeFieldsLayout {
      TextField(String(localized: .settingsPayEditorOvertimeFrom), text: $rule.from)
        .textInputAutocapitalization(.never)
        .keyboardType(.numbersAndPunctuation)
        .textFieldStyle(.roundedBorder)

      TextField(String(localized: .settingsPayEditorOvertimeTo), text: $rule.to)
        .textInputAutocapitalization(.never)
        .keyboardType(.numbersAndPunctuation)
        .textFieldStyle(.roundedBorder)

      TextField(
        String(localized: .settingsPayEditorOvertimePercent),
        value: $rule.percent,
        format: .number.precision(.fractionLength(0...1))
      )
      .keyboardType(.decimalPad)
      .textFieldStyle(.roundedBorder)

      Button(action: onDelete) {
        Image(systemName: "trash")
          .foregroundColor(.tidexError)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
          .accessibilityHidden(true)
      }
      .accessibilityLabel(Text(.settingsAccessibilityDeleteOvertimeRule(ruleSummary)))
      .buttonStyle(.plain)
    }
  }

  /// The days and hours the rule covers, used to name the rule for VoiceOver.
  private var ruleSummary: String {
    let days = rule.days.sorted().map(dayShortName).joined(separator: ", ")
    return "\(days) \(String(localized: .calendarAccessibilityTimeRange(rule.from, rule.to)))"
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
}

struct OvertimeRuleDraft: Identifiable, Equatable {
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
