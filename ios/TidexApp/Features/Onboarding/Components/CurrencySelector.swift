import SwiftUI

/// Currency selector for onboarding
/// Shows current currency with a dropdown to select from available options
struct CurrencySelector: View {
  @Binding var selectedCurrency: String

  @State private var showingPicker = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      // Label
      Text(.onboardingCurrencyLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      // Selector button
      Button(action: {
        Haptics.play(.light)
        showingPicker = true
      }) {
        HStack {
          Text(CurrencyConfig.get(selectedCurrency).label)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)

          Spacer()

          Image(systemName: "chevron.down")
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexTextMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .stroke(Color.tidexBorder, lineWidth: 1)
        )
      }
      .buttonStyle(.plain)
    }
    .sheet(isPresented: $showingPicker) {
      OnboardingCurrencyPickerSheet(
        selectedCurrency: $selectedCurrency,
        isPresented: $showingPicker
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }
}

/// Capsule-style currency selector used in pre-auth simulator header.
struct OnboardingCurrencyCapsuleSelector: View {
  @Binding var selectedCurrency: String

  @State private var showingPicker = false

  var body: some View {
    Button(action: {
      Haptics.play(.light)
      showingPicker = true
    }) {
      HStack(spacing: Spacing.xxxs) {
        Text(CurrencyConfig.get(selectedCurrency).value)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextSecondary)
          .lineLimit(1)

        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundColor(.tidexTextMuted)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
    }
    .buttonStyle(.plain)
    .tidexGlass(shape: .capsule, interactive: true)
    .accessibilityLabel(Text(.onboardingCurrencyTitle))
    .sheet(isPresented: $showingPicker) {
      OnboardingCurrencyPickerSheet(
        selectedCurrency: $selectedCurrency,
        isPresented: $showingPicker
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }
}

// MARK: - Currency Picker Sheet

struct OnboardingCurrencyPickerSheet: View {
  @Binding var selectedCurrency: String
  @Binding var isPresented: Bool

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
                      selectedCurrency = option.value
                      isPresented = false
                    }
                  )
                }
              } header: {
                HStack {
                  Text(group.localizedLabel)
                    .font(.tidexFootnoteStrong)
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)
                  Spacer()
                }
                .padding(.horizontal, Spacing.mlg)
                .padding(.vertical, Spacing.xs)
                .background(Color.tidexBackground)
              }
            }
          }
          .padding(.top, Spacing.xs)
        }
      }
      .navigationTitle(String(localized: .onboardingCurrencyTitle))
      .navigationBarTitleDisplayMode(.inline)
      .sensoryFeedback(.impact(weight: .light), trigger: selectedCurrency)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
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
          .font(isSelected ? .tidexHeadline : .tidexBody)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.tidexButton)
            .foregroundColor(.tidexBrandPrimary)
        }
      }
      .contentShape(Rectangle())
      .padding(.horizontal, Spacing.mlg)
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

    OnboardingCurrencyCapsuleSelector(selectedCurrency: .constant("$"))
      .padding()
  }
  .background(Color.tidexBackground)
}
