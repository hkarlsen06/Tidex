import SwiftUI

// MARK: - Wage Source Selector

/// Toggle between tariff (preset rates) and custom wage
/// Shows appropriate input for each mode
struct WageSourceSelector: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var usePreset: Bool
  @Binding var wageLevel: Int
  @Binding var customWage: Double
  let currency: String
  /// When false, only shows custom wage input (hides tariff toggle)
  /// Used when user's currency is not "kr" (Norwegian krone)
  var showTariffOption: Bool = true
  /// The matching tariff version, when it has been loaded.
  var tariffVersion: TariffVersion?  // swiftlint:disable:this explicit_acl
  /// Preserve a saved rate until the user explicitly selects a tariff rate.
  var savedTariffRate: Double?
  /// Optional content shown between selector buttons and the tariff/custom input list.
  var selectorFooterContent: AnyView?  // swiftlint:disable:this explicit_acl
  var selectorDetailsContent: AnyView?  // swiftlint:disable:this explicit_acl

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Offer loaded categories, or preserve only the existing saved wage.
  private var tariffLevels: [TariffLevel] {
    if let version = tariffVersion {
      return TariffLevel.from(tariffVersion: version)
    }
    if let savedTariffRate {
      return [
        TariffLevel(
          level: wageLevel, rate: savedTariffRate,
          label: String(localized: .settingsPayEditorCurrentWage))
      ]
    }
    return []
  }

  /// Get wage rate for a specific level
  private func wageRate(for level: Int) -> Double {
    if level == wageLevel, let savedTariffRate {
      return savedTariffRate
    }
    if let version = tariffVersion {
      return version.rate(forLevel: level) ?? 0
    }
    return 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Section header
      Text(.settingsPayEditorWageSource)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)
        .accessibilityAddTraits(.isHeader)

      // Toggle buttons: Tariff vs Custom (only show if tariff is available)
      if showTariffOption {
        sourceToggleButtons
      }

      if let selectorFooterContent {
        selectorFooterContent
      }

      // Content based on selection
      if usePreset, showTariffOption {
        tariffLevelPicker
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
      } else {
        customWageSlider
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
      }

      if !usePreset || !showTariffOption { currentWageDisplay }
      if let selectorDetailsContent { selectorDetailsContent }
    }
    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: usePreset)
    .sensoryFeedback(.selection, trigger: usePreset)
    .sensoryFeedback(.selection, trigger: wageLevel)
  }

  private var sourceToggleButtons: some View {
    HStack(spacing: Spacing.sm) {
      WageTypeToggleButton(
        title: String(localized: .onboardingWageTariff),
        icon: "building.2",
        isSelected: usePreset,
        action: {
          withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            usePreset = true
          }
        }
      )

      WageTypeToggleButton(
        title: String(localized: .onboardingWageCustom),
        icon: "slider.horizontal.3",
        isSelected: !usePreset,
        action: {
          withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            usePreset = false
          }
        }
      )
    }
  }

  // MARK: - Tariff Level Picker

  @ViewBuilder
  private var tariffLevelPicker: some View {
    if !tariffLevels.isEmpty {
      TariffCategorySelector(
        levels: tariffLevels.map {
          TariffLevel(level: $0.level, rate: wageRate(for: $0.level), label: $0.label)
        }, selectedLevel: $wageLevel)
    }
  }

  // MARK: - Custom Wage Slider

  @ViewBuilder
  private var customWageSlider: some View {
    OnboardingRateSlider(
      value: $customWage,
      currency: currency,
      style: .full
    )
  }

  // MARK: - Current Wage Display

  @ViewBuilder
  private var currentWageDisplay: some View {
    let currentWage =
      (usePreset && showTariffOption)
      ? wageRate(for: wageLevel)
      : customWage

    currentWageLayout {
      Text(.settingsPayEditorCurrentWage)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      if !dynamicTypeSize.isAccessibilitySize {
        Spacer()
      }

      Text(formatWage(currentWage))
        .accessibilityIdentifier("pay-settings.hourly-wage")
        .font(.tidexButton)
        .foregroundColor(.tidexTextPrimary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .padding(Spacing.sm)
    .background(Color.tidexBrandPrimary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
  }

  private var currentWageLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
      : AnyLayout(HStackLayout())
  }

  private func formatWage(_ wage: Double) -> String {
    let formatted = CurrencyConfig.formatPlain(wage, includeDecimals: true)
    let currencyConfig = CurrencyConfig.get(currency)
    let perHour = String(localized: .commonPerHourShort)

    switch currencyConfig.display {
    case .prefix:
      return "\(currency)\(formatted)\(perHour)"

    case .suffix:
      return "\(formatted) \(currency)\(perHour)"
    }
  }
}

// MARK: - Wage Type Toggle Button

private struct WageTypeToggleButton: View {
  let title: String
  let icon: String
  let isSelected: Bool
  let action: () -> Void
  @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 20

  var body: some View {
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        Image(systemName: icon)
          .font(.system(size: iconSize))
          .accessibilityHidden(true)
          .foregroundColor(isSelected ? .tidexBlueText : .tidexTextMuted)

        Text(title)
          .font(isSelected ? .tidexLabelStrong : .tidexLabel)
          .foregroundColor(isSelected ? .tidexTextPrimary : .tidexTextSecondary)
      }
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 72)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(
            isSelected ? Color.tidexBlueText : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Tariff Level Selection Row
