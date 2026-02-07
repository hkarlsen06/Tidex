import SwiftUI
import UIKit

/// Screen for configuring break, tax, and payday with progressive accordion
/// Each section expands one at a time for focused input
struct SettingsAccordionScreen: View {
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  var onBack: (() -> Void)? = nil

  @State private var currentSection: SettingsSection = .breakDeduction
  @State private var completedSections: Set<SettingsSection> = []
  @State private var showingTaxInput = false
  @State private var taxInputText = ""
  @FocusState private var isTaxInputFocused: Bool
  @State private var showingPaydayInput = false
  @State private var paydayInputText = ""
  @FocusState private var isPaydayInputFocused: Bool

  private enum SettingsSection: Int, CaseIterable {
    case breakDeduction = 0
    case tax = 1
    case payday = 2
  }

  private let payrollDayOptions = [1, 10, 15, 20, 25, 28]
  private let taxPresets: [Double] = [22, 25, 30, 40]

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            // Back button (if provided)
            if let onBack = onBack {
              HStack {
                Button(action: {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  onBack()
                }) {
                  HStack(spacing: Spacing.xxs) {
                    Image(systemName: "chevron.left")
                      .font(.tidexButton)
                    Text(.commonBack)
                      .font(.tidexBody)
                  }
                  .foregroundColor(.tidexBlue)
                }
                .buttonStyle(.plain)
                Spacer()
              }
              .padding(.horizontal, Spacing.lg)
              .padding(.top, Spacing.md)
              .adaptiveContentWidth()
            }

            Spacer()
              .frame(height: onBack != nil ? 24 : 60)

            // Header
            VStack(spacing: Spacing.sm) {
              Text(.onboardingSettingsTitle)
                .font(.tidexLargeTitle)
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

              Text(.onboardingSettingsSubtitle)
                .font(.tidexBody)
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: Spacing.xl)

            // Accordion sections
            VStack(spacing: Spacing.sm) {
              // Break deduction section
              breakSection

              // Tax section
              taxSection

              // Payday section
              paydaySection
            }
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: Spacing.xxxl)
          }
        }

        // Final continue button (visible when all sections complete)
        if allSectionsComplete {
          OnboardingButton(
            title: String(localized: .commonContinue),
            action: {
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              onContinue()
            }
          )
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, Spacing.xl)
          .adaptiveContentWidth()
          .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentSection)
      .animation(.spring(response: 0.35, dampingFraction: 0.85), value: completedSections)
    }
  }

  private var allSectionsComplete: Bool {
    completedSections.count == SettingsSection.allCases.count
  }

  // MARK: - Break Section

  @ViewBuilder
  private var breakSection: some View {
    AccordionSectionView(
      title: String(localized: .onboardingSettingsBreakTitle),
      summary: breakSummary,
      isExpanded: currentSection == .breakDeduction,
      isComplete: completedSections.contains(.breakDeduction),
      onContinue: {
        completeSection(.breakDeduction)
      }
    ) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Toggle(isOn: $data.breakEnabled) {
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(.onboardingSettingsBreakEnable)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)

            Text(.onboardingSettingsBreakHint)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
          }
        }
        .tint(.tidexBrandPrimary)

        if data.breakEnabled {
          Text(.onboardingSettingsBreakDefault)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tidexBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
    }
    .onTapGesture {
      // Allow tapping if not current section (to expand/edit)
      if currentSection != .breakDeduction {
        withAnimation {
          currentSection = .breakDeduction
        }
      }
    }
  }

  private var breakSummary: String {
    if data.breakEnabled {
      return String(localized: .onboardingSettingsBreakEnabledSummary)
    } else {
      return String(localized: .onboardingSettingsBreakDisabledSummary)
    }
  }

  // MARK: - Tax Section

  @ViewBuilder
  private var taxSection: some View {
    AccordionSectionView(
      title: String(localized: .onboardingSettingsTaxTitle),
      summary: taxSummary,
      isExpanded: currentSection == .tax,
      isComplete: completedSections.contains(.tax),
      onContinue: {
        completeSection(.tax)
      }
    ) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Toggle(isOn: $data.taxEnabled) {
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(.onboardingSettingsTaxEnable)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)

            Text(.onboardingSettingsTaxHint)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
          }
        }
        .tint(.tidexBrandPrimary)

        if data.taxEnabled {
          VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(.onboardingSettingsTaxPercentage)
              .font(.tidexLabel)
              .foregroundColor(.tidexTextSecondary)

            // Tax preset buttons
            HStack(spacing: Spacing.xs) {
              ForEach(taxPresets, id: \.self) { preset in
                TaxPresetButton(
                  value: preset,
                  isSelected: data.taxPercentage == preset,
                  action: {
                    withAnimation {
                      data.taxPercentage = preset
                    }
                  }
                )
              }
            }

            // Current value display - tappable
            HStack {
              if showingTaxInput {
                // Editable input field
                HStack(spacing: Spacing.xxs) {
                  TextField("", text: $taxInputText)
                    .font(.tidexTitle2)
                    .foregroundColor(.tidexBlue)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .focused($isTaxInputFocused)
                    .frame(width: 60)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, 2)
                    .background(Color.tidexBlue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                      RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.tidexBlue, lineWidth: 2)
                    )
                    .onChange(of: isTaxInputFocused) { _, focused in
                      if !focused {
                        applyTaxInput()
                      }
                    }
                    .toolbar {
                      ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(String(localized: .commonDone)) {
                          applyTaxInput()
                        }
                        .fontWeight(.semibold)
                      }
                    }

                  Text("%")
                    .font(.tidexLabel)
                    .foregroundColor(.tidexTextMuted)
                }
              } else {
                // Tappable display
                Button(action: {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  taxInputText = formatTaxValue(data.taxPercentage)
                  showingTaxInput = true
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTaxInputFocused = true
                  }
                }) {
                  HStack(spacing: 2) {
                    Text(formatTaxValue(data.taxPercentage))
                      .font(.tidexTitle2)
                      .foregroundColor(.tidexBlue)
                      .contentTransition(.numericText())
                    Text("%")
                      .font(.tidexLabel)
                      .foregroundColor(.tidexTextMuted)
                  }
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Color.tidexBlue.opacity(0.08))
                  .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
              }
              Spacer()
            }

            Slider(
              value: $data.taxPercentage,
              in: 0...50,
              step: 1,
              onEditingChanged: { isEditing in
                if isEditing {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
              }
            )
            .tint(.tidexBlue)
          }
        }
      }
    }
    .onTapGesture {
      // Allow tapping if: already completed (to edit) OR unlocked and not yet completed
      if currentSection != .tax
        && (completedSections.contains(.tax) || completedSections.contains(.breakDeduction))
      {
        withAnimation {
          currentSection = .tax
        }
      }
    }
    .opacity(completedSections.contains(.breakDeduction) || currentSection == .tax ? 1 : 0.5)
  }

  private var taxSummary: String {
    if data.taxEnabled {
      return "\(Int(data.taxPercentage))%"
    } else {
      return String(localized: .onboardingSettingsTaxDisabledSummary)
    }
  }

  // MARK: - Payday Section

  @ViewBuilder
  private var paydaySection: some View {
    AccordionSectionView(
      title: String(localized: .onboardingSettingsPaydayTitle),
      summary: paydaySummary,
      isExpanded: currentSection == .payday,
      isComplete: completedSections.contains(.payday),
      onContinue: {
        completeSection(.payday)
      }
    ) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(.onboardingSettingsPaydayHint)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)

        // Horizontal scroll with day options + custom input
        // Overlay with fade gradient to hint there's more content
        ZStack(alignment: .trailing) {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
              ForEach(payrollDayOptions, id: \.self) { day in
                PaydayButton(
                  day: day,
                  isLast: day == 28,
                  isSelected: data.payrollDay == day && !showingPaydayInput,
                  action: {
                    showingPaydayInput = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                      data.payrollDay = day
                    }
                  }
                )
              }

              // Custom day input button/field
              if showingPaydayInput {
                HStack(spacing: Spacing.xxs) {
                  TextField("", text: $paydayInputText)
                    .font(.tidexButton)
                    .foregroundColor(.tidexBlue)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($isPaydayInputFocused)
                    .frame(width: 44)
                    .frame(minHeight: 44)
                    .background(Color.tidexBlue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.tidexBlue, lineWidth: 2)
                    )
                    .onChange(of: isPaydayInputFocused) { _, focused in
                      if !focused {
                        applyPaydayInput()
                      }
                    }
                    .toolbar {
                      ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(String(localized: .commonDone)) {
                          applyPaydayInput()
                        }
                        .fontWeight(.semibold)
                      }
                    }
                }
              } else {
                // "Other" button to enter custom day
                Button(action: {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  paydayInputText =
                    !payrollDayOptions.contains(data.payrollDay) ? "\(data.payrollDay)" : ""
                  showingPaydayInput = true
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPaydayInputFocused = true
                  }
                }) {
                  HStack(spacing: Spacing.xxs) {
                    Image(systemName: "pencil")
                      .font(.tidexCaptionRegular)
                    Text(.onboardingSettingsPaydayOther)
                  }
                  .font(
                    !payrollDayOptions.contains(data.payrollDay) ? .tidexLabelStrong : .tidexLabel
                  )
                  .foregroundColor(
                    !payrollDayOptions.contains(data.payrollDay) ? .white : .tidexTextSecondary
                  )
                  .frame(minWidth: 56, minHeight: 44)
                  .padding(.horizontal, Spacing.xs)
                  .background(
                    !payrollDayOptions.contains(data.payrollDay)
                      ? Color.tidexBrandPrimary : Color.tidexBackground
                  )
                  .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                  .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                      .stroke(
                        !payrollDayOptions.contains(data.payrollDay)
                          ? Color.clear : Color.tidexBorder, lineWidth: 1)
                  )
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.trailing, Spacing.lg)  // Extra padding for fade area
          }

          // Trailing fade gradient to hint more content
          LinearGradient(
            colors: [Color.tidexSurfaceSecondary.opacity(0), Color.tidexSurfaceSecondary],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: 32)
          .allowsHitTesting(false)
        }

        // Show current custom value if not a preset
        if !payrollDayOptions.contains(data.payrollDay) && !showingPaydayInput {
          Text(String(localized: .onboardingSettingsPaydayCustomValue(data.payrollDay)))
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
        }
      }
    }
    .onTapGesture {
      // Allow tapping if: already completed (to edit) OR unlocked and not yet completed
      if currentSection != .payday
        && (completedSections.contains(.payday) || completedSections.contains(.tax))
      {
        withAnimation {
          currentSection = .payday
        }
      }
    }
    .opacity(completedSections.contains(.tax) || currentSection == .payday ? 1 : 0.5)
  }

  private var paydaySummary: String {
    if data.payrollDay == 28 {
      return String(localized: .onboardingPersonalizePaydayLastDay)
    } else {
      return "\(data.payrollDay)."
    }
  }

  // MARK: - Helpers

  private func completeSection(_ section: SettingsSection) {
    withAnimation {
      completedSections.insert(section)

      // Move to next section
      switch section {
      case .breakDeduction:
        currentSection = .tax
      case .tax:
        currentSection = .payday
      case .payday:
        // All done - button will appear
        break
      }
    }
  }

  private func formatTaxValue(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    formatter.locale = Locale(identifier: "nb_NO")
    return formatter.string(from: NSNumber(value: value)) ?? "0"
  }

  private func applyTaxInput() {
    // Parse the input, handling both comma and period as decimal separator
    let normalized = taxInputText.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(normalized) {
      // Clamp to valid range (0-50%)
      let clamped = min(max(parsed, 0), 50)
      let rounded = (clamped * 10).rounded() / 10
      data.taxPercentage = rounded
    }
    showingTaxInput = false
    isTaxInputFocused = false
  }

  private func applyPaydayInput() {
    if let parsed = Int(paydayInputText) {
      // Clamp to valid range (1-28)
      let clamped = min(max(parsed, 1), 28)
      data.payrollDay = clamped
    }
    showingPaydayInput = false
    isPaydayInputFocused = false
  }
}

// MARK: - Tax Preset Button

private struct TaxPresetButton: View {
  let value: Double
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      action()
    }) {
      Text("\(Int(value))%")
        .font(isSelected ? .tidexLabelStrong : .tidexLabel)
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexBackground)
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Payday Button

private struct PaydayButton: View {
  let day: Int
  let isLast: Bool
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      action()
    }) {
      Text(isLast ? String(localized: .onboardingPersonalizePaydayLastDay) : "\(day)")
        .font(isSelected ? .tidexButton : .tidexBodyMedium)
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .frame(minWidth: 56, minHeight: 44)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  SettingsAccordionScreen(data: OnboardingData(), onContinue: {})
}
