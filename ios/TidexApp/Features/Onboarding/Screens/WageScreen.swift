import SwiftUI
import UIKit

/// Screen for choosing wage type and selecting tariff level or custom rate
/// Used in post-auth onboarding and add-job setup
struct WageScreen: View {
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  var onBack: (() -> Void)? = nil

  @State private var isLoadingTariffData = false
  @State private var showingTariffDisabledInfoAlert = false

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            // Back button (if not first screen)
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
              Text(.onboardingWageTitle)
                .font(.tidexScreenTitle)
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

              Text(.onboardingWageSubtitle)
                .font(.tidexBody)
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 32)

            // Wage type toggle
            wageTypeToggle
              .padding(.horizontal, Spacing.lg)
              .adaptiveContentWidth()

            Spacer()
              .frame(height: 24)

            // Content based on wage type
            Group {
              switch data.wageType {
              case .tariff:
                tariffSelector
              case .custom:
                customWageContent
              }
            }
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()

            // Bottom padding to account for fixed button
            Spacer()
              .frame(height: 120)
          }
        }
        .scrollDismissesKeyboard(.interactively)

        // Fixed continue button at bottom
        VStack(spacing: 0) {
          // Gradient fade
          LinearGradient(
            colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 24)

          OnboardingButton(
            title: String(localized: .commonContinue),
            action: {
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              onContinue()
            }
          )
          .padding(.horizontal, Spacing.lg)
          .adaptiveContentWidth()

          Spacer()
            .frame(height: Spacing.xl)
        }
        .background(Color.tidexBackground)
      }
    }
    .alert(
      String(localized: "onboarding.wage.tariff_disabled_info.title", table: "Localizable"),
      isPresented: $showingTariffDisabledInfoAlert
    ) {
      Button(String(localized: .alertsOk), role: .cancel) {}
    } message: {
      Text(
        String(localized: "onboarding.wage.tariff_disabled_info.message", table: "Localizable")
      )
    }
    .onAppear {
      if !data.hasInitializedWageForLocale {
        // Initialize custom wage based on currency's wage range tier (only once)
        let currencyConfig = CurrencyConfig.get(data.currency)
        data.customHourlyWage = currencyConfig.wageRangeTier.defaultValue
        data.hasInitializedWageForLocale = true
      }

      // Load tariff data if not already loaded
      if data.availableTariffTypes.isEmpty {
        Task {
          await loadTariffData()
        }
      }
    }
    .task {
      // Ensure tariff version is loaded for the selected type
      if data.currentTariffVersion == nil && data.wageType == .tariff {
        await loadTariffVersion(for: data.selectedTariffTypeId)
      }
    }
    .onChange(of: data.wageType) { _, newType in
      // Tariff uses kr (Norwegian krone) - reset currency when switching to tariff
      if newType == .tariff {
        data.currency = "kr"
      }
    }
    .onChange(of: data.currency) { oldCurrency, newCurrency in
      // When currency changes, check if wage range tier changed
      // If so, reset to the new tier's default value
      let oldTier = CurrencyConfig.get(oldCurrency).wageRangeTier
      let newTier = CurrencyConfig.get(newCurrency).wageRangeTier
      if oldTier != newTier {
        data.customHourlyWage = newTier.defaultValue
      }
    }
  }

  // MARK: - Wage Type Toggle

  @ViewBuilder
  private var wageTypeToggle: some View {
    let isTariffEnabled = data.currency == "kr"

    HStack(spacing: Spacing.sm) {
      WageTypeButton(
        title: String(localized: .onboardingWageCustom),
        isSelected: data.wageType == .custom,
        isEnabled: true,
        action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            data.wageType = .custom
          }
        }
      )

      WageTypeButton(
        title: String(localized: .onboardingWageTariff),
        isSelected: data.wageType == .tariff,
        isEnabled: isTariffEnabled,
        action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            data.wageType = .tariff
          }
        },
        onDisabledTap: {
          showingTariffDisabledInfoAlert = true
        }
      )
    }
  }

  // MARK: - Tariff Selector

  /// Tariff levels to display - from version if available, otherwise static fallback
  private var tariffLevels: [TariffLevel] {
    if let version = data.currentTariffVersion {
      return TariffLevel.from(tariffVersion: version)
    }
    return TariffLevel.all
  }

  @ViewBuilder
  private var tariffSelector: some View {
    VStack(spacing: Spacing.md) {
      // Tariff type picker (when multiple types available)
      if !data.availableTariffTypes.isEmpty {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(.settingsPayEditorTariffTypeLabel)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)

          Menu {
            ForEach(data.availableTariffTypes) { tariffType in
              Button(action: {
                guard tariffType.id != data.selectedTariffTypeId else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                data.selectedTariffTypeId = tariffType.id
                Task {
                  await loadTariffVersion(for: tariffType.id)
                }
              }) {
                HStack {
                  Text(tariffType.display_name)
                  if tariffType.id == data.selectedTariffTypeId {
                    Image(systemName: "checkmark")
                  }
                }
              }
            }
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: Spacing.micro) {
                Text(selectedTariffTypeName)
                  .font(.tidexBodyMedium)
                  .foregroundColor(.tidexTextPrimary)

                if let version = data.currentTariffVersion {
                  Text(
                    "\(String(localized: .settingsPayEditorTariffEffectiveDate)): \(formatEffectiveDate(version.effective_date))"
                  )
                  .font(.tidexFootnote)
                  .foregroundColor(.tidexTextSecondary)
                }
              }

              Spacer()

              Image(systemName: "chevron.up.chevron.down")
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextMuted)
            }
            .padding(Spacing.sm)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .stroke(Color.tidexBorder, lineWidth: 1)
            )
          }
        }
      }

      // Tariff level picker
      VStack(spacing: Spacing.sm) {
        ForEach(tariffLevels) { level in
          TariffLevelRow(
            level: level,
            isSelected: data.selectedTariffLevel == level.level,
            action: {
              withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                data.selectedTariffLevel = level.level
              }
            }
          )
        }
      }
    }
  }

  private var selectedTariffTypeName: String {
    data.availableTariffTypes.first { $0.id == data.selectedTariffTypeId }?.display_name
      ?? data.selectedTariffTypeId
  }

  private func formatEffectiveDate(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: dateString) else { return dateString }

    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  // MARK: - Custom Wage Content

  @ViewBuilder
  private var customWageContent: some View {
    VStack(spacing: Spacing.mlg) {
      // Currency selector
      CurrencySelector(selectedCurrency: $data.currency)

      // Wage slider
      OnboardingRateSlider(
        value: $data.customHourlyWage,
        currency: data.currency,
        style: .full
      )
    }
  }

  // MARK: - Tariff Data Loading

  private func loadTariffData() async {
    isLoadingTariffData = true
    defer { isLoadingTariffData = false }

    do {
      // Load available tariff types
      let types = try await TariffVersionService.shared.getTariffTypes()
      await MainActor.run {
        data.availableTariffTypes = types

        // Set default tariff type if not already set
        if let defaultType = types.first(where: { $0.is_default }) ?? types.first {
          if data.selectedTariffTypeId.isEmpty
            || !types.contains(where: { $0.id == data.selectedTariffTypeId })
          {
            data.selectedTariffTypeId = defaultType.id
          }
        }
      }

      // Load latest version for the selected tariff type
      await loadTariffVersion(for: data.selectedTariffTypeId)
    } catch {
      // Silently fail - will use static fallback rates
      print("Failed to load tariff data: \(error)")
    }
  }

  private func loadTariffVersion(for tariffTypeId: String) async {
    do {
      let version = try await TariffVersionService.shared.getLatestTariffVersion(
        tariffType: tariffTypeId)
      await MainActor.run {
        data.currentTariffVersion = version
      }
    } catch {
      // Silently fail - will use static fallback rates
      print("Failed to load tariff version: \(error)")
    }
  }
}

// MARK: - Wage Type Button

private struct WageTypeButton: View {
  let title: String
  let isSelected: Bool
  let isEnabled: Bool
  let action: () -> Void
  var onDisabledTap: (() -> Void)? = nil

  var body: some View {
    Button(action: {
      guard isEnabled else {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        onDisabledTap?()
        return
      }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      action()
    }) {
      Text(title)
        .font(isSelected ? .tidexButton : .tidexBodyMedium)
        .foregroundColor(textColor)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .stroke(borderColor, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.55)
  }

  private var textColor: Color {
    if isSelected {
      return isEnabled ? .white : .tidexTextMuted
    }
    return isEnabled ? .tidexTextSecondary : .tidexTextMuted
  }

  private var backgroundColor: Color {
    if isSelected {
      return isEnabled ? .tidexBrandPrimary : .tidexSurfaceSecondary
    }
    return .tidexSurfaceSecondary
  }

  private var borderColor: Color {
    if isSelected {
      return isEnabled ? .clear : .tidexBorder
    }
    return .tidexBorder
  }
}

// MARK: - Tariff Level Row

private struct TariffLevelRow: View {
  let level: TariffLevel
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      action()
    }) {
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(level.displayName)
            .font(isSelected ? .tidexButton : .tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)

          Text(level.formattedRate)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        // Selection indicator
        ZStack {
          Circle()
            .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: 2)
            .frame(width: 24, height: 24)

          if isSelected {
            Circle()
              .fill(Color.tidexBrandPrimary)
              .frame(width: 14, height: 14)
          }
        }
      }
      .padding(Spacing.md)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(
            isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  WageScreen(data: OnboardingData(), onContinue: {})
}
