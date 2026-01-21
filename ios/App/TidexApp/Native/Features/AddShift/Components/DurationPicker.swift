import SwiftUI

/// Picker for selecting the end condition of a recurring shift
/// Options: indefinite, X months, X years, or specific end date
struct DurationPicker: View {
    @Binding var endCondition: EndCondition?
    @Environment(\.localization) private var localization

    @State private var durationType: DurationType = .months
    @State private var monthsValue: Int = 6
    @State private var yearsValue: Int = 1
    @State private var endDate: Date = Date().addingTimeInterval(180 * 24 * 60 * 60)  // 6 months ahead

    private enum DurationType: String, CaseIterable, Identifiable {
        case indefinite
        case months
        case years
        case endDate

        var id: String { rawValue }

        var labelKey: String {
            switch self {
            case .indefinite: return "addShift.duration.indefinite"
            case .months: return "addShift.duration.months"
            case .years: return "addShift.duration.years"
            case .endDate: return "addShift.duration.endDate"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Duration type selector
            HStack(spacing: 8) {
                Text(localization.string("addShift.duration"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)

                Spacer()
            }

            // Type buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DurationType.allCases) { type in
                        DurationTypeButton(
                            label: localization.string(type.labelKey),
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
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Indefinite Description

private struct IndefiniteDescription: View {
    @Environment(\.localization) private var localization

    var body: some View {
        HStack {
            Image(systemName: "infinity")
                .font(.system(size: 20))
                .foregroundColor(.tidexBlue)

            Text(localization.string("addShift.indefiniteHint"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Months Slider

private struct MonthsSlider: View {
    @Binding var value: Int
    let onValueChange: () -> Void
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(value == 1
                    ? localization.string("addShift.monthSingular")
                    : localization.string("addShift.monthPlural").replacingOccurrences(of: "{n}", with: "\(value)"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()
            }

            Slider(value: Binding(
                get: { Double(value) },
                set: { newValue in
                    value = Int(newValue)
                    onValueChange()
                }
            ), in: 1...24, step: 1)
            .tint(.tidexBlue)
        }
        .padding(16)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Years Slider

private struct YearsSlider: View {
    @Binding var value: Int
    let onValueChange: () -> Void
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(value == 1
                    ? localization.string("addShift.yearSingular")
                    : localization.string("addShift.yearPlural").replacingOccurrences(of: "{n}", with: "\(value)"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()
            }

            Slider(value: Binding(
                get: { Double(value) },
                set: { newValue in
                    value = Int(newValue)
                    onValueChange()
                }
            ), in: 1...5, step: 1)
            .tint(.tidexBlue)
        }
        .padding(16)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - End Date Picker

private struct EndDatePicker: View {
    @Binding var date: Date
    let onDateChange: () -> Void
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.string("addShift.duration.endDate"))
                .font(.system(size: 14, weight: .medium))
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
        .padding(16)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            DurationPicker(endCondition: .constant(.months(value: 6)))
            DurationPicker(endCondition: .constant(nil))
        }
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
