import SwiftUI

/// Workplace name with a status line for the default or unfinished job.
struct PaySettingsJobHeader: View {
  let name: String?
  let colorHex: String?
  let isDefault: Bool
  let isConfigured: Bool

  var body: some View {
    if let name {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        WorkplaceNameText(
          name: name,
          colorHex: colorHex,
          font: .tidexScreenTitle,
          fallbackBadgeColor: .tidexBlue,
          lineLimit: 2,
          maxTextAlignment: .leading,
          badgeCornerRadius: CornerRadius.md,
          badgeHorizontalPadding: Spacing.sm
        )
        .multilineTextAlignment(.leading)

        if isDefault {
          Label {
            Text(.settingsPayJobActionsStandardStatus)
          } icon: {
            Image(systemName: "checkmark.circle.fill")
          }
          .font(.tidexFootnote)
          .foregroundColor(.tidexBlueText)
        } else if !isConfigured {
          Label {
            Text(.settingsPaySetupRequiredBadge)
          } icon: {
            Image(systemName: "exclamationmark.circle.fill")
          }
          .font(.tidexFootnote)
          .foregroundColor(.tidexWarning)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
