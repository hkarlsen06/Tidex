import SwiftUI
import UIKit

// MARK: - Break Deduction Section

/// Section for configuring break deduction settings
struct BreakDeductionSection: View {
  @Binding var enabled: Bool
  @Binding var method: BreakMethod
  @Binding var thresholdHours: Double
  @Binding var deductionMinutes: Int
  @State private var isAdvancedExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Section header with toggle
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.settingsPayEditorBreakTitle)
            .font(.tidexButton)
            .foregroundColor(.tidexTextPrimary)

          Text(.settingsPayEditorBreakDescription)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        Toggle("", isOn: $enabled)
          .labelsHidden()
          .tint(.tidexBrandPrimary)
          .onChange(of: enabled) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
          }
      }

      // Settings (only shown when enabled)
      if enabled {
        VStack(spacing: Spacing.md) {
          advancedMethodDisclosure
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
    .onAppear {
      normalizeMethodIfNeeded()
    }
    .onChange(of: enabled) { _, isEnabled in
      guard isEnabled else { return }
      normalizeMethodIfNeeded()
    }
  }

  // MARK: - Break Method Picker

  @ViewBuilder
  private var advancedMethodDisclosure: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.18)) {
          isAdvancedExpanded.toggle()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(.settingsPayEditorBreakAdvanced)
              .font(.tidexLabel)
              .foregroundColor(.tidexTextPrimary)

            Text(methodTitle(for: method))
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextSecondary)
          }

          Spacer()

          Image(systemName: "chevron.down")
            .font(.tidexCaption)
            .foregroundColor(.tidexTextMuted)
            .rotationEffect(.degrees(isAdvancedExpanded ? 180 : 0))
        }
        .padding(Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
            .fill(Color.tidexSurfaceSecondary)
        )
      }
      .buttonStyle(.plain)

      if isAdvancedExpanded {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          thresholdInput

          deductionInput

          breakMethodPicker

          Text(.settingsPayEditorBreakMethodGuidance)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.sm)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
            .fill(Color.tidexSurfaceSecondary.opacity(0.55))
        )
        .padding(.top, Spacing.xs)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  @ViewBuilder
  private var breakMethodPicker: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayEditorBreakMethod)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      VStack(spacing: Spacing.xxxs) {
        ForEach(selectableBreakMethods, id: \.self) { breakMethod in
          BreakMethodRow(
            method: breakMethod,
            isSelected: method == breakMethod,
            action: {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                method = breakMethod
              }
            }
          )
        }
      }
    }
  }

  // MARK: - Threshold Input

  @ViewBuilder
  private var thresholdInput: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayEditorBreakThreshold)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      HStack {
        Text(formatThreshold(thresholdHours))
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Stepper("", value: $thresholdHours, in: 1...12, step: 0.5)
          .labelsHidden()
      }
      .padding(Spacing.sm)
      .background(Color.tidexBackground)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
  }

  private func formatThreshold(_ hours: Double) -> String {
    if hours == floor(hours) {
      return String(localized: .settingsPayBreakHours(Int32(Int(hours))))
    } else {
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = 1
      formatter.maximumFractionDigits = 1
      formatter.locale = Locale(identifier: Locale.current.identifier)
      let formatted = formatter.string(from: NSNumber(value: hours)) ?? "\(hours)"
      return String(localized: .settingsPayBreakHoursDecimal(formatted))
    }
  }

  // MARK: - Deduction Input

  @ViewBuilder
  private var deductionInput: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayEditorBreakDeduction)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      HStack {
        Text(formatDeduction(deductionMinutes))
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Stepper("", value: $deductionMinutes, in: 5...120, step: 5)
          .labelsHidden()
      }
      .padding(Spacing.sm)
      .background(Color.tidexBackground)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
  }

  private func formatDeduction(_ minutes: Int) -> String {
    return String(localized: .settingsPayBreakMinutes(Int32(minutes)))
  }

  private func methodTitle(for method: BreakMethod) -> String {
    switch method {
    case .proportional:
      return String(localized: .settingsPayBreakMethodProportional)
    case .baseOnly:
      return String(localized: .settingsPayBreakMethodBaseOnly)
    case .endOfShift:
      return String(localized: .settingsPayBreakMethodEndOfShift)
    case .none:
      return String(localized: .settingsPayBreakMethodNone)
    }
  }

  private var selectableBreakMethods: [BreakMethod] {
    BreakMethod.allCases.filter { $0 != .none }
  }

  private func normalizeMethodIfNeeded() {
    guard enabled, method == .none else { return }
    method = .proportional
  }
}

// MARK: - Break Method Row

private struct BreakMethodRow: View {
  let method: BreakMethod
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(methodTitle)
            .font(isSelected ? .tidexLabelStrong : .tidexLabel)
            .foregroundColor(.tidexTextPrimary)

          Text(methodDescription)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(2)
        }

        Spacer()

        // Selection indicator
        ZStack {
          Circle()
            .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: 1)
            .frame(width: 20, height: 20)

          if isSelected {
            Circle()
              .fill(Color.tidexBrandPrimary)
              .frame(width: 10, height: 10)
          }
        }
      }
      .padding(Spacing.xs)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexBackground)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var methodTitle: String {
    switch method {
    case .proportional:
      return String(localized: .settingsPayBreakMethodProportional)
    case .baseOnly:
      return String(localized: .settingsPayBreakMethodBaseOnly)
    case .endOfShift:
      return String(localized: .settingsPayBreakMethodEndOfShift)
    case .none:
      return String(localized: .settingsPayBreakMethodNone)
    }
  }

  private var methodDescription: String {
    switch method {
    case .proportional:
      return String(localized: .settingsPayBreakMethodDescProportional)
    case .baseOnly:
      return String(localized: .settingsPayBreakMethodDescBaseOnly)
    case .endOfShift:
      return String(localized: .settingsPayBreakMethodDescEndOfShift)
    case .none:
      return String(localized: .settingsPayBreakMethodDescNone)
    }
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    BreakDeductionSection(
      enabled: .constant(true),
      method: .constant(.proportional),
      thresholdHours: .constant(5.5),
      deductionMinutes: .constant(30)
    )
    .padding()
  }
  .background(Color.tidexBackground)
}
