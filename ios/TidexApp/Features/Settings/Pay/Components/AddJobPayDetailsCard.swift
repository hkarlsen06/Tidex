import SwiftUI

extension View {
  /// Padded, bordered surface used by the cards on the add job pages.
  func addJobCardChrome() -> some View {
    padding(Spacing.md)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBorder, lineWidth: 1)
      )
  }
}

/// Payday picker with the common days in a grid and a row below for any other day.
struct AddJobPayDetailsCard: View {
  @Binding var payrollDay: Int
  @Binding var showingPaydayInput: Bool
  @Binding var paydayInputText: String
  var isPaydayInputFocused: FocusState<Bool>.Binding
  let onApplyPaydayInput: () -> Void

  private let payrollDayOptions = [1, 10, 15, 20, 25, 31]

  private var isCustomPayday: Bool {
    !payrollDayOptions.contains(payrollDay)
  }

  // Three columns keep long translations of "Last" readable on small phones.
  private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3)

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.settingsPayAddJobPayrollDay)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      LazyVGrid(columns: columns, spacing: Spacing.xs) {
        ForEach(payrollDayOptions, id: \.self) { day in
          AddJobPaydayButton(
            day: day,
            isLast: day == 31,
            isSelected: payrollDay == day && !showingPaydayInput,
            action: {
              showingPaydayInput = false
              payrollDay = day
            }
          )
        }
      }

      if showingPaydayInput {
        paydayTextField
      } else {
        otherPaydayButton
      }
    }
    .addJobCardChrome()
    .sensoryFeedback(.impact(weight: .light), trigger: showingPaydayInput) { _, new in new }
    .sensoryFeedback(.selection, trigger: payrollDay)
  }

  private var paydayTextField: some View {
    TextField("", text: $paydayInputText, prompt: Text(.settingsPayAddJobPayrollDay))
      .accessibilityLabel(Text(.settingsPayAddJobPayrollDay))
      .font(.tidexButton)
      .foregroundColor(.tidexBlueText)
      .keyboardType(.numberPad)
      .multilineTextAlignment(.center)
      .focused(isPaydayInputFocused)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(Color.tidexBlue.opacity(0.15))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
          .stroke(Color.tidexBlueText, lineWidth: 1)
      )
      .onChange(of: isPaydayInputFocused.wrappedValue) { _, focused in
        if !focused {
          onApplyPaydayInput()
        }
      }
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(String(localized: .commonDone)) {
            onApplyPaydayInput()
          }
          .fontWeight(.semibold)
        }
      }
  }

  private var otherPaydayButton: some View {
    Button(action: {
      paydayInputText = isCustomPayday ? "\(payrollDay)" : ""
      showingPaydayInput = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isPaydayInputFocused.wrappedValue = true
      }
    }) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "pencil")
          .font(.tidexCaptionRegular)
          .accessibilityHidden(true)
        if isCustomPayday {
          Text(.onboardingSettingsPaydayCustomValue(payrollDay))
        } else {
          Text(.onboardingSettingsPaydayOther)
        }
      }
      .font(isCustomPayday ? .tidexLabelStrong : .tidexLabel)
      .foregroundColor(isCustomPayday ? .tidexTextOnBrand : .tidexTextSecondary)
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, Spacing.xs)
      .background(
        isCustomPayday
          ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary.opacity(0.76)
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isCustomPayday ? .isSelected : [])
  }
}

private struct AddJobPaydayButton: View {
  let day: Int
  let isLast: Bool
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(dayText)
        .font(isSelected ? .tidexButton : .tidexBodyMedium)
        .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(.settingsAccessibilityPaydayOption(dayText)))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var dayText: String {
    isLast ? String(localized: .onboardingPersonalizePaydayLastDay) : "\(day)"
  }
}
