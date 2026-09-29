import SwiftUI

/// Sheet for adding/editing a single supplement rule
/// Uses progressive disclosure: Days → Time → Type → Value
struct SupplementRuleEditor: View {
  let rule: OnboardingSupplementRule?
  let currency: String
  let onSave: (OnboardingSupplementRule) -> Void
  let onCancel: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var editedRule: OnboardingSupplementRule
  @State private var currentStep: EditorStep = .days
  @State private var hasSelectedType: Bool = false

  private enum EditorStep: Int, Comparable {
    case days = 0
    case time = 1
    case type = 2
    case value = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
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
              editingLayout
            } else {
              addingLayout(minHeight: geometry.size.height - 150)
            }
          }
          .defaultScrollAnchor(isEditing ? .top : .bottom)

          saveButton
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

  /// Editing mode: normal top-to-bottom layout
  private var editingLayout: some View {
    VStack(spacing: Spacing.lg) {
      daysSection
      timeSection
      typeSection
      valueSection

      Spacer()
        .frame(height: 80)
    }
    .padding(Spacing.lg)
  }

  /// Adding mode: content starts at bottom, pushes up as steps are added
  private func addingLayout(minHeight: CGFloat) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)

      VStack(spacing: Spacing.lg) {
        // Days selector - always visible
        daysSection

        // Time range (visible after days selected)
        if currentStep >= .time {
          timeSection
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }

        // Type toggle (visible after times set)
        if currentStep >= .type {
          typeSection
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }

        // Value input (visible after type selected)
        if currentStep >= .value {
          valueSection
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .padding(Spacing.lg)
      .padding(.bottom, Spacing.bottomScrollMargin)
    }
    .frame(minHeight: minHeight)
    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: currentStep)
    .onChange(of: currentStep) { _, step in
      // New sections appear below the focused control, so tell VoiceOver which one was added.
      switch step {
      case .days:
        break

      case .time:
        AccessibilityNotification.Announcement(String(localized: .onboardingSupplementsTimeLabel)).post()

      case .type:
        AccessibilityNotification.Announcement(String(localized: .onboardingSupplementsTypeLabel)).post()

      case .value:
        AccessibilityNotification.Announcement(String(localized: .onboardingSupplementsValueLabel)).post()
      }
    }
  }

  /// Save button at bottom
  private var saveButton: some View {
    VStack {
      Spacer()

      OnboardingButton(
        title: String(localized: primaryButtonTitle),
        action: {
          handlePrimaryActionTap()
        }
      )
      .disabled(!canSave && !canAdvanceToNextStep)
      .opacity((canSave || canAdvanceToNextStep) ? 1 : 0.5)
      .padding(.horizontal, Spacing.lg)
      .padding(.bottom, Spacing.xl)
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

  // MARK: - Can Save

  private var canSave: Bool {
    !editedRule.days.isEmpty && !editedRule.fromTime.isEmpty && !editedRule.toTime.isEmpty
      && editedRule.value > 0
      && hasSelectedType
  }

  private var canAdvanceToNextStep: Bool {
    switch currentStep {
    case .days:
      return !editedRule.days.isEmpty

    case .time:
      return !editedRule.fromTime.isEmpty && !editedRule.toTime.isEmpty

    case .type:
      return true

    case .value:
      return false
    }
  }

  private var primaryButtonTitle: LocalizedStringResource {
    canSave ? .onboardingSupplementsSave : .commonNext
  }

  private func handlePrimaryActionTap() {
    if canSave {
      Haptics.play(.success)
      onSave(editedRule)
      return
    }

    guard canAdvanceToNextStep else { return }

    Haptics.play(.light)
    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85)) {
      switch currentStep {
      case .days:
        // Pre-filled default times are valid, so allow moving straight to type.
        currentStep =
          (!editedRule.fromTime.isEmpty && !editedRule.toTime.isEmpty)
          ? .type
          : .time

      case .time:
        currentStep = .type

      case .type:
        // Accept the currently shown type as the chosen type when tapping Next.
        hasSelectedType = true
        currentStep = .value

      case .value:
        break
      }
    }
  }

  // MARK: - Value Section

  private var valueSection: some View {
    SupplementValueSection(
      rule: $editedRule,
      currency: currency,
      hourRateSuffix: hourRateSuffix
    )
  }

  // MARK: - Type Section

  @ViewBuilder
  private var typeSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSupplementsTypeLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      HStack(spacing: Spacing.sm) {
        TypeButton(
          title: String(localized: .onboardingSupplementsFixedRate),
          subtitle: hourRateSuffix,
          isSelected: hasSelectedType && editedRule.type == .fixed,
          action: {
            Haptics.play(.light)
            withAnimation(reduceMotion ? nil : .default) {
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
            Haptics.play(.light)
            withAnimation(reduceMotion ? nil : .default) {
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
}

extension SupplementRuleEditor {
  // MARK: - Days Section

  @ViewBuilder
  private var daysSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingSupplementsDaysLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      dayButtonRow

      // Quick select buttons
      quickSelectLayout {
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

  /// The seven day buttons sit in one row, and wrap into a grid when large text makes them too wide.
  @ViewBuilder
  private var dayButtonRow: some View {
    if dynamicTypeSize.isAccessibilitySize {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 44), spacing: Spacing.xs)],
        alignment: .leading,
        spacing: Spacing.xs
      ) {
        dayButtons
      }
    } else {
      HStack(spacing: Spacing.xs) {
        dayButtons
      }
    }
  }

  @ViewBuilder
  private var dayButtons: some View {
    ForEach(1...7, id: \.self) { day in
      DayButton(
        day: day,
        isSelected: editedRule.days.contains(day),
        action: {
          Haptics.play(.light)
          withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8)) {
            if editedRule.days.contains(day) {
              editedRule.days.remove(day)
            } else {
              editedRule.days.insert(day)
            }

            // Advance to time step if we have at least one day
            if !editedRule.days.isEmpty, currentStep == .days {
              withAnimation(reduceMotion ? nil : .default) {
                currentStep = .time
              }
            }
          }
        }
      )
    }
  }

  private var quickSelectLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.xs))
  }

  private func advanceIfNeeded() {
    if currentStep == .days, !editedRule.days.isEmpty {
      withAnimation(reduceMotion ? nil : .default) {
        currentStep = .time
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

      TimeRangePicker(
        startTime: supplementStartTimeBinding,
        endTime: supplementEndTimeBinding,
        showsRecentTimeChips: false
      )
      .onChange(of: editedRule.fromTime) { _, _ in
        advanceFromTimeStepIfReady()
      }
      .onChange(of: editedRule.toTime) { _, _ in
        advanceFromTimeStepIfReady()
      }
    }
  }

  private var supplementStartTimeBinding: Binding<Date?> {
    Binding(
      get: { parseSupplementTime(editedRule.fromTime) },
      set: { newValue in
        editedRule.fromTime = formatSupplementTime(newValue)
      }
    )
  }

  private var supplementEndTimeBinding: Binding<Date?> {
    Binding(
      get: { parseSupplementTime(editedRule.toTime) },
      set: { newValue in
        editedRule.toTime = formatSupplementTime(newValue)
      }
    )
  }

  private func advanceFromTimeStepIfReady() {
    guard currentStep == .time,
      !editedRule.fromTime.isEmpty,
      !editedRule.toTime.isEmpty
    else { return }

    withAnimation(reduceMotion ? nil : .default) {
      currentStep = .type
    }
  }

  private func parseSupplementTime(_ time: String) -> Date? {
    let parts = time.split(separator: ":")
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      hours >= 0,
      hours <= 24,
      minutes >= 0,
      minutes <= 59
    else {
      return nil
    }

    if hours == 24, minutes != 0 { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length no_magic_numbers

    var components = Calendar.gregorianCurrent.dateComponents([.year, .month, .day], from: Date())
    components.hour = hours == 24 ? 0 : hours
    components.minute = minutes
    return Calendar.gregorianCurrent.date(from: components)
  }

  private func formatSupplementTime(_ date: Date?) -> String {
    guard let date else { return "" }
    return FormatterCache.hourMinuteFormatter(timeZone: Date.localTimeZone).string(from: date)
  }
}

#Preview {
  SupplementRuleEditor(
    rule: nil,
    onSave: { _ in },
    onCancel: {}
  )
}
