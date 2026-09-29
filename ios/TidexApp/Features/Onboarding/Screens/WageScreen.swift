import SwiftUI
import UIKit

/// Screen for choosing wage type and selecting tariff level or custom rate
/// Used in post-auth onboarding and add-job setup
struct WageScreen: View {
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  var onBack: (() -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order
  var topTrailingTitle: String?  // swiftlint:disable:this explicit_acl type_contents_order
  var onTopTrailingAction: (() -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order

  @State private var isLoadingTariffData = false
  @State private var tariffLoadFailed = false
  @State private var isKeyboardVisible = false

  private var showsTopBar: Bool {
    onBack != nil || topTrailingTitle != nil
  }

  private enum ScrollTarget: Hashable {
    case customWageContent
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        scrollContent
        continueBar
      }
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
      if data.currentTariffVersion == nil, data.wageType == .tariff {
        await loadTariffVersion(for: data.selectedTariffTypeId)
      }
    }
    .onChange(of: ConnectivityMonitor.shared.isOnline) { _, isOnline in
      // Reload the tariff lists once the connection is back.
      if isOnline, tariffLoadFailed { Task { await loadTariffData() } }
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
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
    { _ in
      withAnimation(.easeOut(duration: 0.18)) {
        isKeyboardVisible = true
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
    { _ in
      withAnimation(.easeOut(duration: 0.18)) {
        isKeyboardVisible = false
      }
    }
  }

  private var scrollContent: some View {
    ScrollViewReader { scrollProxy in
      ScrollView {
        VStack(spacing: 0) {
          // Top actions (if provided)
          if showsTopBar {
            WageTopBar(
              onBack: onBack, title: topTrailingTitle, onTitleAction: onTopTrailingAction)
          }

          Spacer()
            .frame(height: showsTopBar ? 24 : 60)

          header

          Spacer()
            .frame(height: 32)

          wageOptions

          // Bottom padding to account for fixed button
          Spacer()
            .frame(height: isKeyboardVisible ? 88 : 120)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: isKeyboardVisible) { _, visible in
        guard visible, data.wageType == .custom else { return }
        scrollCustomWageInputIntoView(scrollProxy)
      }
    }
  }

  private var header: some View {
    VStack(spacing: Spacing.sm) {
      Text(
        isTariffAvailable
          ? LocalizedStringResource.onboardingWageTitle : .onboardingWageSimpleTitle
      )
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
  }

  @ViewBuilder
  private var wageOptions: some View {
    // Tariffs are Norwegian and priced in kr, so other currencies only get an hourly wage.
    if isTariffAvailable {
      wageTypeToggle
        .padding(.horizontal, Spacing.lg)
        .adaptiveContentWidth()

      Spacer()
        .frame(height: 24)
    }

    // Content based on wage type
    Group {
      switch data.wageType {
      case .tariff:
        WageTariffSelector(data: data) { tariffTypeId in
          Task {
            await loadTariffVersion(for: tariffTypeId)
          }
        }

        if tariffLoadFailed { TariffOfflineHint() }
      case .custom:
        customWageContent
          .id(ScrollTarget.customWageContent)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .adaptiveContentWidth()
  }

  /// Fixed continue button at bottom
  private var continueBar: some View {
    VStack(spacing: 0) {
      // Gradient fade
      LinearGradient(
        colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: isKeyboardVisible ? 12 : 24)

      OnboardingButton(
        title: isKeyboardVisible
          ? String(localized: .commonDone) : String(localized: .commonContinue),
        action: {
          if isKeyboardVisible {
            dismissKeyboard()
          } else {
            Haptics.play(.success)
            onContinue()
          }
        }
      )
      .padding(.horizontal, Spacing.lg)
      .adaptiveContentWidth()

      Spacer()
        .frame(height: isKeyboardVisible ? Spacing.md : Spacing.xl)
    }
    .background(Color.tidexBackground)
  }

  private func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }

  private func scrollCustomWageInputIntoView(_ scrollProxy: ScrollViewProxy) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
      withAnimation(.easeOut(duration: 0.2)) {
        scrollProxy.scrollTo(ScrollTarget.customWageContent, anchor: .bottom)
      }
    }
  }

  // MARK: - Wage Type Toggle

  private var isTariffAvailable: Bool {
    data.currency == "kr"
  }

  @ViewBuilder
  private var wageTypeToggle: some View {
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
        isEnabled: true,
        action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            data.wageType = .tariff
          }
        }
      )
    }
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
        if let defaultType = types.first(where: \.is_default) ?? types.first {
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
      // Static fallback rates stay in use. The offline hint tells the user why.
      tariffLoadFailed = true
    }
  }

  private func loadTariffVersion(for tariffTypeId: String) async {
    do {
      let version = try await TariffVersionService.shared.getLatestTariffVersion(
        tariffType: tariffTypeId)
      await MainActor.run {
        data.currentTariffVersion = version
      }
      tariffLoadFailed = false
    } catch {
      // Static fallback rates stay in use. The offline hint tells the user why.
      tariffLoadFailed = true
    }
  }
}

#Preview {
  WageScreen(data: OnboardingData(), onContinue: {})
}
