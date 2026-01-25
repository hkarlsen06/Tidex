import SwiftUI

/// Currency selector for onboarding
/// Shows current currency with a dropdown to select from available options
struct CurrencySelector: View {
    @Binding var selectedCurrency: String
    @Environment(\.localization) private var localization

    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(localization.string("onboarding.currency.label"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            // Selector button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingPicker = true
            }) {
                HStack {
                    Text(CurrencyConfig.get(selectedCurrency).label)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.tidexTextMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, Spacing.sm)
                .background(Color.tidexSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.tidexBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingPicker) {
            CurrencyPickerSheet(
                selectedCurrency: $selectedCurrency,
                isPresented: $showingPicker
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Currency Picker Sheet

private struct CurrencyPickerSheet: View {
    @Binding var selectedCurrency: String
    @Binding var isPresented: Bool
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(CurrencyConfig.groups) { group in
                            Section {
                                ForEach(group.options) { option in
                                    CurrencyRow(
                                        option: option,
                                        isSelected: selectedCurrency == option.value,
                                        action: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedCurrency = option.value
                                            isPresented = false
                                        }
                                    )
                                }
                            } header: {
                                HStack {
                                    Text(group.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.tidexTextMuted)
                                        .textCase(.uppercase)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.tidexBackground)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(localization.string("onboarding.currency.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.string("common.cancel")) {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Currency Row

private struct CurrencyRow: View {
    let option: CurrencyOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(option.label)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.tidexBrandPrimary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        CurrencySelector(selectedCurrency: .constant("kr"))
            .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
