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
  /// Optional tariff version to use for rates (when nil, uses static fallback)
  var tariffVersion: TariffVersion?  // swiftlint:disable:this explicit_acl
  /// Preserve a saved rate until the user explicitly selects a tariff rate.
  var savedTariffRate: Double?
  /// Optional content shown between selector buttons and the tariff/custom input list.
  var selectorFooterContent: AnyView?  // swiftlint:disable:this explicit_acl

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Tariff levels to display - from version if available, otherwise static fallback
  private var tariffLevels: [TariffLevel] {
    if let version = tariffVersion {
      return TariffLevel.from(tariffVersion: version)
    }
    return TariffLevel.all
  }

  /// Get wage rate for a specific level
  private func wageRate(for level: Int) -> Double {
    if level == wageLevel, let savedTariffRate {
      return savedTariffRate
    }
    if let version = tariffVersion {
      return version.rate(forLevel: level) ?? PayrollCalculator.presetWageRates[String(level)]
        ?? 184.54
    }
    return PayrollCalculator.presetWageRates[String(level)] ?? 184.54
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

      // Current wage display
      currentWageDisplay
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
    VStack(spacing: Spacing.xs) {
      ForEach(tariffLevels) { level in
        TariffLevelSelectionRow(
          level: TariffLevel(level: level.level, rate: wageRate(for: level.level)),
          isSelected: wageLevel == level.level,
          action: {
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
              wageLevel = level.level
            }
          }
        )
      }
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

private struct TariffLevelSelectionRow: View {
  let level: TariffLevel
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(level.displayName)
            .font(isSelected ? .tidexLabelStrong : .tidexLabel)
            .foregroundColor(.tidexTextPrimary)

          Text(level.formattedRate)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        // Selection indicator
        ZStack {
          Circle()
            .stroke(isSelected ? Color.tidexBlueText : Color.tidexBorder, lineWidth: 1)
            .frame(width: Spacing.iconSize, height: Spacing.iconSize)

          if isSelected {
            Circle()
              .fill(Color.tidexBlueText)
              .frame(width: 12, height: 12)
          }
        }
      }
      .padding(Spacing.sm)
      .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
          .stroke(
            isSelected ? Color.tidexBlueText : Color.tidexBorder, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Preview

#Preview {
  VStack {
    WageSourceSelector(
      usePreset: .constant(true),
      wageLevel: .constant(1),
      customWage: .constant(200),
      currency: "kr"
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
