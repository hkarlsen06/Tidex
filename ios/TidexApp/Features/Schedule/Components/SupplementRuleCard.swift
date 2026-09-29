import SwiftUI
import UIKit

// MARK: - Supplement Rule with ID

/// A custom supplement rule with a unique ID for SwiftUI list management
struct CustomSupplementRuleWithId: Identifiable, Equatable {
  let id: String
  var from: String
  var to: String
  var rate: Double?
  var percent: Double?
  /// true = user-added or modified, false/nil = from tariff (predefined)
  var isCustom: Bool

  /// Initialize from a CustomSupplementRule
  init(from rule: CustomSupplementRule, id: String = UUID().uuidString) {
    self.id = id
    self.from = rule.from
    self.to = rule.to
    self.rate = rule.rate
    self.percent = rule.percent
    self.isCustom = rule.isCustom ?? false
  }

  /// Initialize with explicit values
  init(
    id: String = UUID().uuidString,
    from: String,
    to: String,
    rate: Double? = nil,
    percent: Double? = nil,
    isCustom: Bool = true
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.rate = rate
    self.percent = percent
    self.isCustom = isCustom
  }

  /// Convert back to CustomSupplementRule for storage
  func toCustomSupplementRule() -> CustomSupplementRule {
    CustomSupplementRule(
      from: from,
      to: to,
      rate: rate,
      percent: percent,
      isCustom: isCustom
    )
  }

  /// Supplement type based on whether rate or percent is set
  var supplementType: SupplementType {
    if percent != nil {
      return .percent
    }
    return .fixed
  }

  /// Current value (either rate or percent)
  var value: Double {
    percent ?? rate ?? 0
  }

  /// Formatted value string for display
  func formattedValue(currency: String) -> String {
    let currencyConfig = CurrencyConfig.get(currency)
    if let pct = percent {
      return "\(Int(pct))%"
    }
    if let r = rate {
      let formatted = r == floor(r) ? String(format: "%.0f", r) : String(format: "%.1f", r)
      return "\(formatted) \(currencyConfig.value)\(String(localized: .commonPerHourShort))"
    }
    return "-"
  }

  enum SupplementType {
    case fixed
    case percent
  }
}

// MARK: - Shift Supplement Rule Card

/// Card displaying a single supplement rule with edit/delete capabilities
/// Used in the CustomSupplementsEditorSheet for shift-specific supplements
struct ShiftSupplementRuleCard: View {
  let rule: CustomSupplementRuleWithId
  let currency: String
  let onEdit: () -> Void
  let onDelete: () -> Void

  /// Currency configuration for display
  private var currencyConfig: CurrencyOption {
    CurrencyConfig.get(currency)
  }

  var body: some View {
    HStack(spacing: Spacing.sm) {
      // Badge and content
      VStack(alignment: .leading, spacing: Spacing.xs) {
        // Badge
        HStack(spacing: Spacing.xs) {
          Text(
            rule.isCustom
              ? String(localized: .supplementsCustom)
              : String(localized: .supplementsTariff)
          )
          .font(.tidexMicro)
          .foregroundColor(rule.isCustom ? .tidexBlue : .tidexTextSecondary)
          .padding(.horizontal, Spacing.xs)
          .padding(.vertical, 3)
          .background(
            Capsule()
              .fill(
                rule.isCustom
                  ? Color.tidexBlue.opacity(0.15)
                  : Color.tidexSurfaceSecondary)
          )

          Spacer()
        }

        // Time range
        HStack(spacing: Spacing.xxs) {
          Text(rule.from)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)

          Text("–")
            .font(.tidexBody)
            .foregroundColor(.tidexTextMuted)

          Text(rule.to)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
        }

        // Value
        Text(rule.formattedValue(currency: currency))
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      // Actions
      HStack(spacing: Spacing.xs) {
        // Edit button
        Button(action: onEdit) {
          Image(systemName: "pencil")
            .font(.tidexLabel)
            .foregroundColor(.tidexTextPrimary)
            .frame(width: 36, height: 36)
            .background(Color.tidexBlue.opacity(0.1))
            .clipShape(Circle())
            .contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)

        // Delete button
        Button(action: onDelete) {
          Image(systemName: "trash")
            .font(.tidexLabel)
            .foregroundColor(.tidexError)
            .frame(width: 36, height: 36)
            .background(Color.tidexError.opacity(0.1))
            .clipShape(Circle())
            .contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

// MARK: - Supplement Rule Editor Sheet

/// Sheet for editing a single supplement rule (time + type + value)
/// Simplified version without days selection since we're in shift context
struct SupplementRuleEditorSheet: View {
  let rule: CustomSupplementRuleWithId?
  let currency: String
  let onSave: (CustomSupplementRuleWithId) -> Void
  let onCancel: () -> Void

  @State private var fromTime = Date()  // swiftlint:disable:this explicit_type_interface
  @State private var toTime = Date()  // swiftlint:disable:this explicit_type_interface
  @State private var supplementType: CustomSupplementRuleWithId.SupplementType = .fixed
  @State private var value: Double = 45
  @State private var valueInputText: String = ""
  @State private var showingValueInput: Bool = false
  @FocusState private var isValueInputFocused: Bool

  private var isEditing: Bool { rule != nil }

  /// Currency configuration for display
  private var currencyConfig: CurrencyOption {
    CurrencyConfig.get(currency)
  }

  /// Hour suffix for rate display
  private var hourRateSuffix: String {
    let hourPart = String(localized: .commonPerHourShort)
    return "\(currencyConfig.value)\(hourPart)"
  }

  init(
    rule: CustomSupplementRuleWithId?,
    currency: String = "kr",
    onSave: @escaping (CustomSupplementRuleWithId) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.rule = rule
    self.currency = currency
    self.onSave = onSave
    self.onCancel = onCancel

    // Initialize state from rule
    if let existingRule = rule {
      _fromTime = State(initialValue: parseTime(existingRule.from) ?? Date())
      _toTime = State(initialValue: parseTime(existingRule.to) ?? Date())
      _supplementType = State(initialValue: existingRule.supplementType)
      _value = State(initialValue: existingRule.value)
    } else {
      // Defaults for new rule
      _fromTime = State(initialValue: parseTime("21:00") ?? Date())
      _toTime = State(initialValue: parseTime("06:00") ?? Date())
      _supplementType = State(initialValue: .fixed)
      _value = State(initialValue: defaultValue(for: .fixed))
    }
  }

  private func parseTime(_ timeString: String) -> Date? {
    FormatterCache.hourMinuteFormatter().date(from: String(timeString.prefix(5)))
  }

  private func formatTime(_ date: Date) -> String {
    date.toHourMinuteString()
  }

  private func defaultValue(for type: CustomSupplementRuleWithId.SupplementType) -> Double {
    switch type {
    case .fixed:
      switch currencyConfig.wageRangeTier {
      case .high: return 45
      case .medium: return 5
      case .low: return 50
      case .veryLow: return 500
      case .ultraLow: return 5_000  // swiftlint:disable:this no_magic_numbers
      }

    case .percent:
      return 50
    }
  }

  private var canSave: Bool {
    value > 0
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.lg) {
          // Time section
          timeSection

          // Type section
          typeSection

          // Value section
          valueSection
        }
        .padding(Spacing.lg)
      }
      .background(Color.tidexBackground)
      .navigationTitle(
        isEditing
          ? String(localized: .onboardingSupplementsEditRule)
          : String(localized: .onboardingSupplementsAddRule)
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
            saveRule()
          }
          .fontWeight(.semibold)
          .disabled(!canSave)
        }
      }
    }
  }

  // MARK: - Time Section

  @ViewBuilder
  private var timeSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSupplementsTimeLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      HStack(spacing: Spacing.md) {
        // From time
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.onboardingSupplementsFrom)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)

          DatePicker(
            "",
            selection: $fromTime,
            displayedComponents: .hourAndMinute
          )
          .datePickerStyle(.compact)
          .labelsHidden()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))

        // To time
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.onboardingSupplementsTo)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)

          DatePicker(
            "",
            selection: $toTime,
            displayedComponents: .hourAndMinute
          )
          .datePickerStyle(.compact)
          .labelsHidden()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      }
    }
  }

  // MARK: - Type Section

  @ViewBuilder
  private var typeSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSupplementsTypeLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      HStack(spacing: Spacing.sm) {
        typeButton(.fixed, title: .onboardingSupplementsFixedRate, subtitle: hourRateSuffix)
        typeButton(.percent, title: .onboardingSupplementsPercentRate, subtitle: "%")
      }
    }
  }

  private func typeButton(
    _ type: CustomSupplementRuleWithId.SupplementType,
    title: LocalizedStringResource,
    subtitle: String
  ) -> some View {
    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      withAnimation {
        supplementType = type
        value = defaultValue(for: type)
      }
    } label: {
      VStack(spacing: Spacing.xxs) {
        Text(title)
          .font(supplementType == type ? .tidexLabelStrong : .tidexLabel)
          .foregroundColor(supplementType == type ? .tidexTextPrimary : .tidexTextSecondary)

        Text(verbatim: subtitle)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 64)
      .background(
        supplementType == type
          ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(
            supplementType == type ? Color.tidexBrandPrimary : Color.tidexBorder,
            lineWidth: supplementType == type ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Value Section

  @ViewBuilder
  private var valueSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSupplementsValueLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      quickValueButtons

      // Slider with value display
      VStack(spacing: Spacing.xs) {
        HStack {
          if showingValueInput {
            valueInputField
          } else {
            valueDisplayButton
          }
          Spacer()
        }

        Slider(
          value: $value,
          in: valueRange,
          step: 1,
          onEditingChanged: { isEditing in
            if isEditing {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
          }
        )
        .tint(.tidexTextPrimary)
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
  }

  private var quickValueButtons: some View {
    HStack(spacing: Spacing.xs) {
      ForEach(quickValues, id: \.self) { quickValue in
        quickValueButton(quickValue)
      }
    }
  }

  private func quickValueButton(_ quickValue: Double) -> some View {
    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      withAnimation {
        value = quickValue
      }
    } label: {
      Text(supplementType == .fixed ? "+\(Int(quickValue))" : "\(Int(quickValue))%")
        .font(value == quickValue ? .tidexLabelStrong : .tidexLabel)
        .foregroundColor(value == quickValue ? .white : .tidexTextSecondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
          value == quickValue ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary
        )
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(value == quickValue ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }

  /// Editable input field
  private var valueInputField: some View {
    HStack(spacing: Spacing.xxs) {
      valueTextField

      Text(supplementType == .fixed ? hourRateSuffix : "%")
        .font(.tidexLabel)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var valueTextField: some View {
    TextField("", text: $valueInputText)
      .font(.tidexLargeTitle)
      .foregroundColor(.tidexBlue)
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.leading)
      .focused($isValueInputFocused)
      .frame(width: 80)
      .padding(.horizontal, Spacing.xxs)
      .padding(.vertical, Spacing.micro)
      .background(Color.tidexBlue.opacity(0.15))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
          .stroke(Color.tidexBlue, lineWidth: 2)
      )
      .onChange(of: isValueInputFocused) { _, focused in
        if !focused {
          applyValueInput()
        }
      }
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(String(localized: .commonDone)) {
            applyValueInput()
          }
          .fontWeight(.semibold)
        }
      }
  }

  /// Tappable display
  @ViewBuilder
  private var valueDisplayButton: some View {
    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      valueInputText = formatValueWithDecimals(value)
      showingValueInput = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isValueInputFocused = true
      }
    } label: {
      Text(formatValueWithDecimals(value))
        .font(.tidexLargeTitle)
        .foregroundColor(.tidexBlue)
        .contentTransition(.numericText())
        .padding(.horizontal, Spacing.xxs)
        .padding(.vertical, Spacing.micro)
        .background(Color.tidexBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
    }
    .buttonStyle(.plain)

    Text(supplementType == .fixed ? hourRateSuffix : "%")
      .font(.tidexLabel)
      .foregroundColor(.tidexTextMuted)
  }

  private var quickValues: [Double] {
    switch supplementType {
    case .fixed:
      switch currencyConfig.wageRangeTier {
      case .high:
        return [22, 45, 55, 110, 115]

      case .medium:
        return [2, 5, 10, 15, 20]

      case .low:
        return [10, 25, 50, 75, 100]

      case .veryLow:
        return [100, 250, 500, 750, 1_000]  // swiftlint:disable:this no_magic_numbers

      case .ultraLow:
        return [1_000, 2_500, 5_000, 7_500, 10_000]  // swiftlint:disable:this no_magic_numbers
      }

    case .percent:
      return [25, 50, 100, 150]
    }
  }

  private var valueRange: ClosedRange<Double> {
    switch supplementType {
    case .fixed:
      switch currencyConfig.wageRangeTier {
      case .high: return 1...200
      case .medium: return 1...50
      case .low: return 1...500
      case .veryLow: return 1...2_000  // swiftlint:disable:this no_magic_numbers switch_case_on_newline
      case .ultraLow: return 1...20_000  // swiftlint:disable:this no_magic_numbers switch_case_on_newline
      }

    case .percent:
      return 1...200
    }
  }

  private func formatValueWithDecimals(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).locale(.appLocale))
  }

  private func applyValueInput() {
    let normalized = valueInputText.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(normalized) {
      let clamped = min(max(parsed, valueRange.lowerBound), valueRange.upperBound)
      let rounded = (clamped * 100).rounded() / 100
      value = rounded
    }
    showingValueInput = false
    isValueInputFocused = false
  }

  private func saveRule() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)

    let newRule = CustomSupplementRuleWithId(
      id: rule?.id ?? UUID().uuidString,
      from: formatTime(fromTime),
      to: formatTime(toTime),
      rate: supplementType == .fixed ? value : nil,
      percent: supplementType == .percent ? value : nil,
      isCustom: true  // Always mark as custom when edited/added
    )

    onSave(newRule)
  }
}

// MARK: - Preview

#Preview("Rule Card") {
  VStack(spacing: Spacing.md) {
    ShiftSupplementRuleCard(
      rule: CustomSupplementRuleWithId(
        from: "21:00",
        to: "06:00",
        rate: 45,
        isCustom: false
      ),
      currency: "kr",
      onEdit: {},
      onDelete: {}
    )

    ShiftSupplementRuleCard(
      rule: CustomSupplementRuleWithId(
        from: "18:00",
        to: "22:00",
        percent: 50,
        isCustom: true
      ),
      currency: "kr",
      onEdit: {},
      onDelete: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Editor Sheet - New") {
  SupplementRuleEditorSheet(
    rule: nil,
    currency: "kr",
    onSave: { _ in },
    onCancel: {}
  )
}

#Preview("Editor Sheet - Edit") {
  SupplementRuleEditorSheet(
    rule: CustomSupplementRuleWithId(
      from: "21:00",
      to: "06:00",
      rate: 45,
      isCustom: false
    ),
    currency: "kr",
    onSave: { _ in },
    onCancel: {}
  )
}
