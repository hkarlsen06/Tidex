import SwiftUI

/// Shown when tariff data could not be loaded and the built-in rates are in use.
struct TariffOfflineHint: View {
  var body: some View {
    Text(.onboardingWageTariffOffline)
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
    return TariffLevel.all
  }

  var body: some View {
    VStack(spacing: Spacing.md) {
      Text(.onboardingWageTariffHint)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      // Tariff type picker (when multiple types available)
      if !data.availableTariffTypes.isEmpty {
        tariffTypePicker
      }

      // Tariff level picker
      VStack(spacing: Spacing.sm) {
        ForEach(tariffLevels) { level in
          TariffLevelRow(
            level: level,
            isSelected: data.selectedTariffLevel == level.level,
            action: {
              withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                data.selectedTariffLevel = level.level
              }
            }
          )
        }
      }
    }
  }

  private var tariffTypePicker: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayEditorTariffTypeLabel)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      Menu {
        ForEach(data.availableTariffTypes) { tariffType in
          Button(action: {
            guard tariffType.id != data.selectedTariffTypeId else { return }
            data.selectedTariffTypeId = tariffType.id
            onTariffTypeChanged(tariffType.id)
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
        tariffTypeMenuLabel
      }
      .sensoryFeedback(.impact(weight: .light), trigger: data.selectedTariffTypeId)
    }
  }

  private var tariffTypeMenuLabel: some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(selectedTariffTypeName)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        if let version = data.currentTariffVersion {
          let effectiveDate = formatEffectiveDate(version.effective_date)
          Text("\(String(localized: .settingsPayEditorTariffEffectiveDate)): \(effectiveDate)")
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.settingsPayEditorTariffTypeLabel))
    .accessibilityValue(Text(selectedTariffTypeName))
  }

  private var selectedTariffTypeName: String {
    data.availableTariffTypes.first { $0.id == data.selectedTariffTypeId }?.display_name
      ?? data.selectedTariffTypeId
  }

  private func formatEffectiveDate(_ dateString: String) -> String {
    guard let date = Date.fromISODateString(dateString) else { return dateString }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
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

struct TariffLevelRow: View {
  let level: TariffLevel
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: {
      Haptics.play(.light)
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
        .accessibilityHidden(true)
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
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
