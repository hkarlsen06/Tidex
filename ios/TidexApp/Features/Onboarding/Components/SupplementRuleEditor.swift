import SwiftUI
import UIKit

/// Sheet for adding/editing a single supplement rule
/// Uses progressive disclosure: Days → Time → Type → Value
struct SupplementRuleEditor: View {
  let rule: OnboardingSupplementRule?
  let currency: String
  let onSave: (OnboardingSupplementRule) -> Void
  let onCancel: () -> Void

  @State private var editedRule: OnboardingSupplementRule
  @State private var currentStep: EditorStep = .days
  @State private var hasSelectedType: Bool = false
  @State private var showingValueInput = false
  @State private var valueInputText = ""
  @FocusState private var isValueInputFocused: Bool

  private enum EditorStep: Int, Comparable {
    case days = 0
    case time = 1
    case type = 2
    case value = 3

    static func < (lhs: EditorStep, rhs: EditorStep) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  init(
    rule: OnboardingSupplementRule?,
    currency: String = "kr",
    onSave: @escaping (OnboardingSupplementRule) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.rule = rule
    self.currency = currency
    self.onSave = onSave
    self.onCancel = onCancel
    self._editedRule = State(initialValue: rule ?? OnboardingSupplementRule())
    // If editing an existing rule, show all sections immediately
    let isEditing = rule != nil
    self._hasSelectedType = State(initialValue: isEditing)
    self._currentStep = State(initialValue: isEditing ? .value : .days)
  }

  private var isEditing: Bool {
    rule != nil
  }

  /// Currency configuration for display
  private var currencyConfig: CurrencyOption {
    CurrencyConfig.get(currency)
  }

  /// Hour suffix for rate display (e.g., "kr/t", "$/hr")
  private var hourRateSuffix: String {
    let hourPart = String(localized: .commonPerHourShort)
    return currencyConfig.display == .prefix
      ? "\(currencyConfig.value)\(hourPart)"
      : "\(currencyConfig.value)\(hourPart)"
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ZStack {
          Color.tidexBackground
            .ignoresSafeArea()

          ScrollView {
            if isEditing {
              // Editing mode: normal top-to-bottom layout
              VStack(spacing: 24) {
                daysSection
                timeSection
                typeSection
                valueSection

                Spacer()
                  .frame(height: 80)
              }
              .padding(24)
            } else {
              // Adding mode: content starts at bottom, pushes up as steps are added
              VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 24) {
                  // Days selector - always visible
                  daysSection

                  // Time range (visible after days selected)
                  if currentStep >= .time {
                    timeSection
                      .transition(.opacity.combined(with: .move(edge: .bottom)))
                  }

                  // Type toggle (visible after times set)
                  if currentStep >= .type {
                    typeSection
                      .transition(.opacity.combined(with: .move(edge: .bottom)))
                  }

                  // Value input (visible after type selected)
                  if currentStep >= .value {
                    valueSection
                      .transition(.opacity.combined(with: .move(edge: .bottom)))
                  }
                }
                .padding(24)
                .padding(.bottom, 80)
              }
              .frame(minHeight: geometry.size.height - 150)
              .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentStep)
            }
          }
          .defaultScrollAnchor(isEditing ? .top : .bottom)

          // Save button at bottom
          VStack {
            Spacer()

            OnboardingButton(
              title: String(localized: .onboardingSupplementsSave),
              action: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSave(editedRule)
              }
            )
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(
              LinearGradient(
                colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
                startPoint: .top,
                endPoint: .bottom
              )
              .frame(height: 100)
              .allowsHitTesting(false)
            )
          }
        }
      }
      .navigationTitle(
        rule == nil
          ? String(localized: .onboardingSupplementsAddRule)
          : String(localized: .onboardingSupplementsEditRule)
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            onCancel()
          }
        }
      }
    }
  }

  // MARK: - Can Save

  private var canSave: Bool {
    !editedRule.days.isEmpty && !editedRule.fromTime.isEmpty && !editedRule.toTime.isEmpty
      && editedRule.value > 0
  }

  // MARK: - Days Section

  @ViewBuilder
  private var daysSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(.onboardingSupplementsDaysLabel)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.tidexTextSecondary)

      HStack(spacing: 8) {
        ForEach(1...7, id: \.self) { day in
          DayButton(
            day: day,
            isSelected: editedRule.days.contains(day),
            action: {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                if editedRule.days.contains(day) {
                  editedRule.days.remove(day)
                } else {
                  editedRule.days.insert(day)
                }

                // Advance to time step if we have at least one day
                if !editedRule.days.isEmpty && currentStep == .days {
                  withAnimation {
                    currentStep = .time
                  }
                }
              }
            }
          )
        }
      }

      // Quick select buttons
      HStack(spacing: 8) {
        QuickSelectButton(title: String(localized: .onboardingSupplementsWeekdays)) {
          editedRule.days = Set([1, 2, 3, 4, 5])
          advanceIfNeeded()
        }

        QuickSelectButton(title: String(localized: .onboardingSupplementsWeekend)) {
          editedRule.days = Set([6, 7])
          advanceIfNeeded()
        }

        QuickSelectButton(title: String(localized: .onboardingSupplementsAllDays)) {
          editedRule.days = Set(1...7)
          advanceIfNeeded()
        }
      }
    }
  }

  private func advanceIfNeeded() {
    if currentStep == .days && !editedRule.days.isEmpty {
      withAnimation {
        currentStep = .time
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
        TimePickerField(
          label: String(localized: .onboardingSupplementsFrom),
          time: $editedRule.fromTime,
          onChange: {
            if currentStep == .time {
              withAnimation {
                currentStep = .type
              }
            }
          }
        )

        TimePickerField(
          label: String(localized: .onboardingSupplementsTo),
          time: $editedRule.toTime,
          onChange: {
            if currentStep == .time {
              withAnimation {
                currentStep = .type
              }
            }
          }
        )
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
        TypeButton(
          title: String(localized: .onboardingSupplementsFixedRate),
          subtitle: hourRateSuffix,
          isSelected: hasSelectedType && editedRule.type == .fixed,
          action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation {
              editedRule.type = .fixed
              hasSelectedType = true
              if currentStep == .type {
                currentStep = .value
              }
            }
          }
        )

        TypeButton(
          title: String(localized: .onboardingSupplementsPercentRate),
          subtitle: "%",
          isSelected: hasSelectedType && editedRule.type == .percent,
          action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation {
              editedRule.type = .percent
              hasSelectedType = true
              if currentStep == .type {
                currentStep = .value
              }
            }
          }
        )
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
        ForEach(quickValues, id: \.self) { value in
          QuickValueButton(
            value: value,
            type: editedRule.type,
            isSelected: editedRule.value == value,
            action: {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              withAnimation {
                editedRule.value = value
              }
            }
          )
        }
      }

      // Slider for fine-tuning
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

              Text(editedRule.type == .fixed ? hourRateSuffix : "%")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextMuted)
            }
          } else {
            // Tappable display
            Button(action: {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              valueInputText = formatValueWithDecimals(editedRule.value)
              showingValueInput = true
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isValueInputFocused = true
              }
            }) {
              Text(formatValueWithDecimals(editedRule.value))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.tidexBlue)
                .contentTransition(.numericText())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.tidexBlue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(editedRule.type == .fixed ? hourRateSuffix : "%")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.tidexTextMuted)
          }
          Spacer()
        }

        Slider(
          value: $editedRule.value,
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

  private func formatValueWithDecimals(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    formatter.locale = Locale(identifier: "nb_NO")
    return formatter.string(from: NSNumber(value: value)) ?? "0"
  }

  private func applyValueInput() {
    // Parse the input, handling both comma and period as decimal separator
    let normalized = valueInputText.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(normalized) {
      // Clamp to valid range and round to 2 decimal places
      let clamped = min(max(parsed, valueRange.lowerBound), valueRange.upperBound)
      let rounded = (clamped * 100).rounded() / 100
      editedRule.value = rounded
    }
    showingValueInput = false
    isValueInputFocused = false
  }

  private var quickValues: [Double] {
    switch editedRule.type {
    case .fixed:
      // Quick values based on currency tier
      switch currencyConfig.wageRangeTier {
      case .high:
        // NOK, CZK, Ruble - higher nominal values
        return [22, 45, 55, 110, 115]
      case .medium:
        // USD, EUR, GBP, etc. - lower nominal values
        return [2, 5, 10, 15, 20]
      case .low:
        // INR, BRL, ZAR, etc. - mid-range nominal values
        return [10, 25, 50, 75, 100]
      case .veryLow:
        // JPY, KRW - very high nominal values
        return [100, 250, 500, 750, 1000]
      }
    case .percent:
      return [25, 50, 100, 150]
    }
  }

  private var valueRange: ClosedRange<Double> {
    switch editedRule.type {
    case .fixed:
      // Value range based on currency tier
      switch currencyConfig.wageRangeTier {
      case .high:
        return 1...200
      case .medium:
        return 1...50
      case .low:
        return 1...500
      case .veryLow:
        return 1...2000
      }
    case .percent:
      return 1...200
    }
  }
}

// MARK: - Day Button

private struct DayButton: View {
  let day: Int
  let isSelected: Bool
  let action: () -> Void

  private let dayLabels = ["M", "T", "O", "T", "F", "L", "S"]

  var body: some View {
    Button(action: action) {
      Text(dayLabels[day - 1])
        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .frame(width: 40, height: 40)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
        .clipShape(Circle())
        .overlay(
          Circle()
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Quick Select Button

private struct QuickSelectButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      action()
    }) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.tidexBlue)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tidexBlue.opacity(0.08))
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Time Picker Field

private struct TimePickerField: View {
  let label: String
  @Binding var time: String
  let onChange: () -> Void

  @State private var selectedDate: Date = Date()

  init(label: String, time: Binding<String>, onChange: @escaping () -> Void) {
    self.label = label
    self._time = time
    self.onChange = onChange

    // Parse initial time
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    if let date = formatter.date(from: time.wrappedValue) {
      self._selectedDate = State(initialValue: date)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 12))
        .foregroundColor(.tidexTextMuted)

      DatePicker(
        "",
        selection: $selectedDate,
        displayedComponents: .hourAndMinute
      )
      .datePickerStyle(.compact)
      .labelsHidden()
      .onChange(of: selectedDate) { _, newValue in
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        time = formatter.string(from: newValue)
        onChange()
      }
    }
    .frame(maxWidth: .infinity)
    .padding(12)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

// MARK: - Type Button

private struct TypeButton: View {
  let title: String
  let subtitle: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
          .foregroundColor(isSelected ? .tidexTextPrimary : .tidexTextSecondary)

        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.tidexTextMuted)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 64)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(
            isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Quick Value Button

private struct QuickValueButton: View {
  let value: Double
  let type: OnboardingSupplementRule.SupplementType
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(type == .fixed ? "+\(Int(value))" : "\(Int(value))%")
        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  SupplementRuleEditor(
    rule: nil,
    onSave: { _ in },
    onCancel: {}
  )
}
