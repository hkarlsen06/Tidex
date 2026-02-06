import SwiftUI
import UIKit

// MARK: - Break Deduction Section

/// Section for configuring break deduction settings
struct BreakDeductionSection: View {
  @Binding var enabled: Bool
  @Binding var method: BreakMethod
  @Binding var thresholdHours: Double
  @Binding var deductionMinutes: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Section header with toggle
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(.settingsPayEditorBreakTitle)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.tidexTextPrimary)

          Text(.settingsPayEditorBreakDescription)
            .font(.system(size: 13))
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
        VStack(spacing: 16) {
          // Break method picker
          breakMethodPicker

          // Threshold hours
          thresholdInput

          // Deduction minutes
          deductionInput
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
  }

  // MARK: - Break Method Picker

  @ViewBuilder
  private var breakMethodPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(.settingsPayEditorBreakMethod)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.tidexTextSecondary)

      VStack(spacing: 6) {
        ForEach(BreakMethod.allCases, id: \.self) { breakMethod in
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
    VStack(alignment: .leading, spacing: 8) {
      Text(.settingsPayEditorBreakThreshold)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.tidexTextSecondary)

      HStack {
        Text(formatThreshold(thresholdHours))
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Stepper("", value: $thresholdHours, in: 1...12, step: 0.5)
          .labelsHidden()
      }
      .padding(12)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    VStack(alignment: .leading, spacing: 8) {
      Text(.settingsPayEditorBreakDeduction)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.tidexTextSecondary)

      HStack {
        Text(formatDeduction(deductionMinutes))
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Stepper("", value: $deductionMinutes, in: 5...120, step: 5)
          .labelsHidden()
      }
      .padding(12)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  private func formatDeduction(_ minutes: Int) -> String {
    return String(localized: .settingsPayBreakMinutes(Int32(minutes)))
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
        VStack(alignment: .leading, spacing: 2) {
          Text(methodTitle)
            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
            .foregroundColor(.tidexTextPrimary)

          Text(methodDescription)
            .font(.system(size: 12))
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(2)
        }

        Spacer()

        // Selection indicator
        ZStack {
          Circle()
            .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: 2)
            .frame(width: 20, height: 20)

          if isSelected {
            Circle()
              .fill(Color.tidexBrandPrimary)
              .frame(width: 10, height: 10)
          }
        }
      }
      .padding(Spacing.xs)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
