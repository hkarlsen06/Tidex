// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_empty_block no_magic_numbers shorthand_optional_binding superfluous_else
import SwiftUI

/// Compact indicator for sync status
/// Shows only when sync is in progress, failed, or offline
struct SyncStatusIndicator: View {
  let syncStatusManager = SyncStatusManager.shared

  var showsOfflineRetry = false
  var onRetry: () -> Void

  private var retryButton: some View {
    Button(action: onRetry) {
      Text(.commonRetry)
        .font(.tidexFootnoteStrong)
        .foregroundStyle(Color.tidexBlueText)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("sync.retry")
  }

  var body: some View {
    switch syncStatusManager.status {
    case .synced:
      EmptyView()

    case .syncing:
      HStack(spacing: Spacing.xs) {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle())
          .scaleEffect(0.8)

        Text(.syncSyncing)
          .font(.tidexFootnoteMedium)
          .foregroundStyle(Color.tidexTextSecondary)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexSurfacePrimary)
      .clipShape(.rect(cornerRadius: CornerRadius.card))
      .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("sync.status")

    case .failed(_, let lastSync):
      HStack(spacing: Spacing.xs) {
        Image(systemName: "exclamationmark.icloud")
          .accessibilityHidden(true)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexWarning)
          .accessibilityHidden(true)

        if let lastSync {
          Text(String(localized: .syncFailedWithLastSync(formatRelativeTime(lastSync))))
            .font(.tidexFootnoteMedium)
            .foregroundStyle(Color.tidexTextSecondary)
        } else {
          Text(.syncSyncFailed)
            .font(.tidexFootnoteMedium)
            .foregroundStyle(Color.tidexTextSecondary)
        }

        retryButton
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexWarning.opacity(0.12))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.card)
          .stroke(Color.tidexWarning.opacity(0.25), lineWidth: 1)
      )
      .clipShape(.rect(cornerRadius: CornerRadius.card))

    case .offline:
      HStack(spacing: Spacing.xs) {
        Image(systemName: "wifi.slash")
          .accessibilityHidden(true)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexTextMuted)
          .accessibilityHidden(true)

        Text(.syncOffline)
          .font(.tidexFootnoteMedium)
          .foregroundStyle(Color.tidexTextMuted)

        if showsOfflineRetry {
          retryButton
        }
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexSurfacePrimary)
      .clipShape(.rect(cornerRadius: CornerRadius.card))
      .accessibilityElement(children: showsOfflineRetry ? .contain : .combine)
      .accessibilityIdentifier("sync.status")
    }
  }

  // MARK: - Helpers

  /// Format a date as relative time (e.g., "5m ago", "1h ago")
  private func formatRelativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    let minutes = Int(interval / 60)

    if minutes < 1 {
      return String(localized: .syncJustNow)
    }
    if minutes < 60 {
      return String(localized: .syncMinutesAgo(Int32(minutes)))
    }
    let hours = minutes / 60
    return String(localized: .syncHoursAgo(Int32(hours)))
  }
}

#Preview("Syncing") {
  VStack(spacing: Spacing.mlg) {
    SyncStatusIndicator(onRetry: {})
  }
  .padding()
  .background(Color.tidexBackground)
  .onAppear {
    SyncStatusManager.shared.syncStarted()
  }
}

#Preview("Failed") {
  VStack(spacing: Spacing.mlg) {
    SyncStatusIndicator(onRetry: {})
  }
  .padding()
  .background(Color.tidexBackground)
  .onAppear {
    SyncStatusManager.shared.syncFailed(message: "Network error")
  }
}

#Preview("Offline") {
  VStack(spacing: Spacing.mlg) {
    SyncStatusIndicator(onRetry: {})
  }
  .padding()
  .background(Color.tidexBackground)
  .onAppear {
    SyncStatusManager.shared.setOffline()
  }
}
