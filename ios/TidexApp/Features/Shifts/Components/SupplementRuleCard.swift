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
      return "\(formatted) \(currencyConfig.value)/t"
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
    HStack(spacing: 12) {
      // Badge and content
      VStack(alignment: .leading, spacing: 8) {
        // Badge
        HStack(spacing: 8) {
          Text(
            rule.isCustom
              ? String(localized: .supplementsCustom)
              : String(localized: .supplementsTariff)
          )
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(rule.isCustom ? .tidexBlue : .tidexTextSecondary)
          .padding(.horizontal, 8)
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
        HStack(spacing: 4) {
          Text(rule.from)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.tidexTextPrimary)

          Text("–")
            .font(.system(size: 16))
            .foregroundColor(.tidexTextMuted)

          Text(rule.to)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.tidexTextPrimary)
        }

        // Value
        Text(rule.formattedValue(currency: currency))
          .font(.system(size: 14))
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      // Actions
      HStack(spacing: 8) {
        // Edit button
        Button(action: onEdit) {
          Image(systemName: "pencil")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.tidexBlue)
            .frame(width: 36, height: 36)
            .background(Color.tidexBlue.opacity(0.1))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)

        // Delete button
        Button(action: onDelete) {
          Image(systemName: "trash")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.tidexError)
            .frame(width: 36, height: 36)
            .background(Color.tidexError.opacity(0.1))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .tidexCardShadow(cornerRadius: 12)
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

  @State private var fromTime: Date = Date()
  @State private var toTime: Date = Date()
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
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.date(from: String(timeString.prefix(5)))
  }

  private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  private func defaultValue(for type: CustomSupplementRuleWithId.SupplementType) -> Double {
    switch type {
    case .fixed:
      switch currencyConfig.wageRangeTier {
      case .high: return 45
      case .medium: return 5
      case .low: return 50
      case .veryLow: return 500
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
        VStack(spacing: 24) {
          // Time section
          timeSection

          // Type section
          typeSection

          // Value section
          valueSection
        }
        .padding(24)
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
    VStack(alignment: .leading, spacing: 12) {
      Text(.onboardingSupplementsTimeLabel)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.tidexTextSecondary)

      HStack(spacing: 16) {
        // From time
        VStack(alignment: .leading, spacing: 4) {
          Text(.onboardingSupplementsFrom)
            .font(.system(size: 12))
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
        .padding(12)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        // To time
        VStack(alignment: .leading, spacing: 4) {
          Text(.onboardingSupplementsTo)
            .font(.system(size: 12))
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
        .padding(12)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
    }
  }

  // MARK: - Type Section

  @ViewBuilder
  private var typeSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(.onboardingSupplementsTypeLabel)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.tidexTextSecondary)

      HStack(spacing: 12) {
        // Fixed rate button
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          withAnimation {
            supplementType = .fixed
            value = defaultValue(for: .fixed)
          }
        } label: {
          VStack(spacing: 4) {
            Text(.onboardingSupplementsFixedRate)
              .font(.system(size: 14, weight: supplementType == .fixed ? .semibold : .medium))
              .foregroundColor(supplementType == .fixed ? .tidexTextPrimary : .tidexTextSecondary)

            Text(hourRateSuffix)
              .font(.system(size: 12))
              .foregroundColor(.tidexTextMuted)
          }
          .frame(maxWidth: .infinity)
          .frame(height: 64)
          .background(
            supplementType == .fixed
              ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary
          )
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(
                supplementType == .fixed ? Color.tidexBrandPrimary : Color.tidexBorder,
                lineWidth: supplementType == .fixed ? 2 : 1)
          )
        }
        .buttonStyle(.plain)

        // Percent button
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          withAnimation {
            supplementType = .percent
            value = defaultValue(for: .percent)
          }
        } label: {
          VStack(spacing: 4) {
            Text(.onboardingSupplementsPercentRate)
              .font(.system(size: 14, weight: supplementType == .percent ? .semibold : .medium))
              .foregroundColor(supplementType == .percent ? .tidexTextPrimary : .tidexTextSecondary)

            Text("%")
              .font(.system(size: 12))
              .foregroundColor(.tidexTextMuted)
          }
          .frame(maxWidth: .infinity)
          .frame(height: 64)
          .background(
            supplementType == .percent
              ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary
          )
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(
                supplementType == .percent ? Color.tidexBrandPrimary : Color.tidexBorder,
                lineWidth: supplementType == .percent ? 2 : 1)
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - Value Section

  @ViewBuilder
  private var valueSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(.onboardingSupplementsValueLabel)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.tidexTextSecondary)

      // Quick value buttons
      HStack(spacing: 8) {
        ForEach(quickValues, id: \.self) { quickValue in
          Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation {
              value = quickValue
            }
          } label: {
            Text(supplementType == .fixed ? "+\(Int(quickValue))" : "\(Int(quickValue))%")
              .font(.system(size: 14, weight: value == quickValue ? .semibold : .medium))
              .foregroundColor(value == quickValue ? .white : .tidexTextSecondary)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
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
      }

      // Slider with value display
      VStack(spacing: 8) {
        HStack {
          if showingValueInput {
            // Editable input field
            HStack(spacing: 4) {
              TextField("", text: $valueInputText)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.tidexBlue)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .focused($isValueInputFocused)
                .frame(width: 80)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.tidexBlue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
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

              Text(supplementType == .fixed ? hourRateSuffix : "%")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextMuted)
            }
          } else {
            // Tappable display
            Button {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              valueInputText = formatValueWithDecimals(value)
              showingValueInput = true
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isValueInputFocused = true
              }
            } label: {
              Text(formatValueWithDecimals(value))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.tidexBlue)
                .contentTransition(.numericText())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.tidexBlue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(supplementType == .fixed ? hourRateSuffix : "%")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.tidexTextMuted)
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
        .tint(.tidexBlue)
      }
      .padding(16)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
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
        return [100, 250, 500, 750, 1000]
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
      case .veryLow: return 1...2000
      }
    case .percent:
      return 1...200
    }
  }

  private func formatValueWithDecimals(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    formatter.locale = Locale(identifier: "nb_NO")
    return formatter.string(from: NSNumber(value: value)) ?? "0"
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
  VStack(spacing: 16) {
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
