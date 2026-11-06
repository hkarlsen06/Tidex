import SwiftUI

/// Shown when no matching tariff data could be loaded.
struct TariffOfflineHint: View {
  var body: some View {
    Text(.tariffUnavailable)
      .font(.tidexFootnote)
      .foregroundColor(.tidexWarning)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Tariff type menu and tariff level list for the wage screen.
struct WageTariffSelector: View {
  @Bindable var data: OnboardingData
  /// Called after the user picks a different tariff type so the caller can load its version.
  let onTariffTypeChanged: (String) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Tariff levels to display - from version if available, otherwise static fallback
  private var tariffLevels: [TariffLevel] {
    if let version = data.currentTariffVersion {
      return TariffLevel.from(tariffVersion: version)
    }
    return []
  }

  var body: some View {
    VStack(spacing: Spacing.md) {
      if !data.availableTariffTypes.isEmpty {
        TariffSetupSelector(
          types: data.availableTariffTypes, selectedTypeID: data.selectedTariffTypeId,
          draft: $data.tariffSelectionDraft
        ) {
          id, previousID in
          let previous = data.availableTariffTypes.first { $0.id == previousID }
          let next = data.availableTariffTypes.first { $0.id == id }
          data.selectedTariffTypeId = id ?? ""
          data.currentTariffVersion = nil
          if let id {
            if !TariffSelection.canPreserveCategory(from: previous, to: next) {
              data.selectedTariffLevel = 0
            }
            onTariffTypeChanged(id)
          }
        }
      }

      if !tariffLevels.isEmpty {
        TariffCategorySelector(levels: tariffLevels, selectedLevel: $data.selectedTariffLevel)
      }
      if let version = data.currentTariffVersion {
        TariffCalculationCoverage(overtime: version.effectiveOvertime)
        TariffSourceDetails(version: version)
      }
    }
  }
}

/// Back button and optional trailing action shown above the wage screen header.
struct WageTopBar: View {
  let onBack: (() -> Void)?
  let title: String?
  let onTitleAction: (() -> Void)?

  var body: some View {
    HStack {
      if let onBack {
        Button(action: {
          Haptics.play(.light)
          onBack()
        }) {
          HStack(spacing: Spacing.xxs) {
            Image(systemName: "chevron.left")
              .font(.tidexButton)
              .accessibilityHidden(true)
            Text(.commonBack)
              .font(.tidexBody)
          }
          .foregroundColor(.tidexBlueText)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        Spacer(minLength: 0)
      }

      Spacer()

      if let title, let onTitleAction {
        WageGlassActionButton(title: title, action: onTitleAction)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.md)
    .adaptiveContentWidth()
  }
}

struct WageGlassActionButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexBlueText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.thinMaterial, in: Capsule())
        .overlay(
          Capsule()
            .stroke(Color.tidexBorder.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Wage Type Button

struct WageTypeButton: View {
  let title: String
  let isSelected: Bool
  let isEnabled: Bool
  let action: () -> Void
  var onDisabledTap: (() -> Void)?

  var body: some View {
    Button(action: {
      guard isEnabled else {
        Haptics.play(.warning)
        onDisabledTap?()
        return
      }
      Haptics.play(.light)
      action()
    }) {
      Text(title)
        .font(isSelected ? .tidexButton : .tidexBodyMedium)
        .foregroundColor(textColor)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 48)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .stroke(borderColor, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.55)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var textColor: Color {
    if isSelected {
      return isEnabled ? .tidexTextOnBrand : .tidexTextMuted
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
