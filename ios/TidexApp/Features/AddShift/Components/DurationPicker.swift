import SwiftUI

/// Picker for selecting the end condition of a recurring shift
/// Options: indefinite, X months, X years, or specific end date
struct DurationPicker: View {
  @Binding var endCondition: EndCondition?

  @State private var durationType: DurationType = .months
  @State private var monthsValue: Int = 6
  @State private var yearsValue: Int = 1
  // swiftlint:disable:next explicit_type_interface no_magic_numbers type_contents_order
  @State private var endDate = Date().addingTimeInterval(180 * 24 * 60 * 60)  // 6 months ahead

  private enum DurationType: String, CaseIterable, Identifiable {
    case indefinite
    case months
    case years
    case endDate

    var id: String { rawValue }

    var label: String {
      switch self {
      case .indefinite: return String(localized: .addShiftDurationIndefinite)
      case .months: return String(localized: .addShiftDurationMonths)
      case .years: return String(localized: .addShiftDurationYears)
      case .endDate: return String(localized: .addShiftDurationEndDate)
      }
    }
  }

  var body: some View {
    VStack(spacing: Spacing.md) {
      // Duration type selector
      HStack(spacing: Spacing.xs) {
        Text(.addShiftDuration)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextMuted)
          .textCase(.uppercase)

        Spacer()
      }

      // Type buttons
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.xs) {
          ForEach(DurationType.allCases) { type in
            DurationTypeButton(
              label: type.label,
              isSelected: durationType == type
            ) {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                durationType = type
                updateEndCondition()
              }
            }
          }
        }
      }

      // Value input based on type
      switch durationType {
      case .indefinite:
        IndefiniteDescription()

      case .months:
        MonthsSlider(value: $monthsValue, onValueChange: updateEndCondition)

      case .years:
        YearsSlider(value: $yearsValue, onValueChange: updateEndCondition)

      case .endDate:
        EndDatePicker(date: $endDate, onDateChange: updateEndCondition)
      }
    }
    .onAppear {
      initializeFromEndCondition()
    }
  }

  // MARK: - Helpers

  private func initializeFromEndCondition() {
    switch endCondition {
    case .none:
      durationType = .indefinite

    case .months(let value):
      durationType = .months
      monthsValue = value

    case .years(let value):
      durationType = .years
      yearsValue = value

    case .endDate(let dateString):
      durationType = .endDate
      if let date = Date.fromISODateString(dateString) {
        endDate = date
      }
    }
  }

  private func updateEndCondition() {
    switch durationType {
    case .indefinite:
      endCondition = nil

    case .months:
      endCondition = .months(value: monthsValue)

    case .years:
      endCondition = .years(value: yearsValue)

    case .endDate:
      endCondition = .endDate(date: endDate.toISODateString())
    }
  }
}

// MARK: - Duration Type Button

private struct DurationTypeButton: View {
  let label: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(isSelected ? .tidexLabelStrong : .tidexSubheadline)
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Indefinite Description

private struct IndefiniteDescription: View {

  var body: some View {
    HStack {
      Image(systemName: "infinity")
        .font(.system(size: 20))
        .foregroundColor(.tidexBlue)

      Text(.addShiftIndefiniteHint)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

// MARK: - Months Slider

private struct MonthsSlider: View {
  @Binding var value: Int
  let onValueChange: () -> Void

  var body: some View {
    VStack(spacing: Spacing.sm) {
      HStack {
        Text(
          value == 1
            ? String(localized: .addShiftMonthSingular)
            : String(localized: .addShiftMonthPlural(value))
        )
        .font(.tidexButton)
        .foregroundColor(.tidexTextPrimary)

        Spacer()
      }

      Slider(
        value: Binding(
          get: { Double(value) },
          set: { newValue in
            value = Int(newValue)
            onValueChange()
          }
        ), in: 1...24, step: 1
      )
      .tint(.tidexBlue)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

// MARK: - Years Slider

private struct YearsSlider: View {
  @Binding var value: Int
  let onValueChange: () -> Void

  var body: some View {
    VStack(spacing: Spacing.sm) {
      HStack {
        Text(
          value == 1
            ? String(localized: .addShiftYearSingular)
            : String(localized: .addShiftYearPlural(value))
        )
        .font(.tidexButton)
        .foregroundColor(.tidexTextPrimary)

        Spacer()
      }

      Slider(
        value: Binding(
          get: { Double(value) },
          set: { newValue in
            value = Int(newValue)
            onValueChange()
          }
        ), in: 1...5, step: 1
      )
      .tint(.tidexBlue)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

// MARK: - End Date Picker

private struct EndDatePicker: View {
  @Binding var date: Date
  let onDateChange: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.addShiftDurationEndDate)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      DatePicker(
        "",
        selection: $date,
        in: Date()...,
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .tint(.tidexBlue)
      .onChange(of: date) { _, _ in
        onDateChange()
      }
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    VStack(spacing: Spacing.mlg) {
      DurationPicker(endCondition: .constant(.months(value: 6)))
      DurationPicker(endCondition: .constant(nil))
    }
    .padding()
  }
  .background(Color.tidexBackground)
}
