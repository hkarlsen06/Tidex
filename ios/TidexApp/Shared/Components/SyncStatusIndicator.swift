import SwiftUI

/// Compact indicator for sync status
/// Shows only when sync is in progress, failed, or offline
struct SyncStatusIndicator: View {
    @ObservedObject var syncStatusManager = SyncStatusManager.shared
    
    var onRetry: () -> Void

    var body: some View {
        switch syncStatusManager.status {
        case .synced:
            EmptyView()

        case .syncing:
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)

                Text(.syncSyncing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)

        case .failed(_, let lastSync):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexWarning)

                if let lastSync = lastSync {
                    Text(String(localized: .syncFailedWithLastSync(formatRelativeTime(lastSync))))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.tidexTextSecondary)
                } else {
                    Text(.syncSyncFailed)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.tidexTextSecondary)
                }

                Button(action: onRetry) {
                    Text(.commonRetry)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.tidexBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.tidexWarning.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.tidexWarning.opacity(0.25), lineWidth: 1)
            )
            .cornerRadius(20)

        case .offline:
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextMuted)

                Text(.syncOffline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(20)
        }
    }

    // MARK: - Helpers

    /// Format a date as relative time (e.g., "5m ago", "1h ago")
    private func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return String(localized: .syncJustNow)
        } else if minutes < 60 {
            return String(localized: .syncMinutesAgo(Int32(minutes)))
        } else {
            let hours = minutes / 60
            return String(localized: .syncHoursAgo(Int32(hours)))
        }
    }
}

#Preview("Syncing") {
    VStack(spacing: 20) {
        SyncStatusIndicator(onRetry: {})
    }
    .padding()
    .background(Color.tidexBackground)
    .onAppear {
        SyncStatusManager.shared.syncStarted()
    }
}

#Preview("Failed") {
    VStack(spacing: 20) {
        SyncStatusIndicator(onRetry: {})
    }
    .padding()
    .background(Color.tidexBackground)
    .onAppear {
        SyncStatusManager.shared.syncFailed(message: "Network error")
    }
}

#Preview("Offline") {
    VStack(spacing: 20) {
        SyncStatusIndicator(onRetry: {})
    }
    .padding()
    .background(Color.tidexBackground)
    .onAppear {
        SyncStatusManager.shared.setOffline()
    }
}
