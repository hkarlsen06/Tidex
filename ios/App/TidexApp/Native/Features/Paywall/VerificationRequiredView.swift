import SwiftUI

// MARK: - Verification Required View

/// Shown when server TTL expired AND StoreKit has no entitlement
/// User needs to connect to internet to verify their subscription status
struct VerificationRequiredView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localization) private var localization

    /// Whether currently offline (determines icon and message)
    let isOffline: Bool

    /// Called when user taps retry
    var onRetry: () async -> Void

    /// Called when user taps restore purchases
    var onRestore: () async -> Void

    @State private var isRetrying = false
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Icon
                iconView
                    .padding(.bottom, 16)

                // Title and message
                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.tidexTextPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 16))
                        .foregroundColor(.tidexTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Retry button
                    Button(action: handleRetry) {
                        if isRetrying {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 54)
                    .foregroundColor(.white)
                    .background(Color.tidexBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isRetrying || isRestoring)

                    // Restore purchases button
                    Button(action: handleRestore) {
                        if isRestoring {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Restore Purchases")
                                .font(.system(size: 17, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 54)
                    .foregroundColor(.tidexBlue)
                    .background(Color.tidexBlue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isRetrying || isRestoring)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.tidexBackground)
            .navigationTitle("Verify Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.tidexTextMuted)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var title: String {
        isOffline
            ? "No Internet Connection"
            : "Verify Your Subscription"
    }

    private var message: String {
        isOffline
            ? "Connect to the internet to verify your subscription status."
            : "We couldn't verify your subscription. Please try again or restore your purchases."
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor.opacity(0.15))
                .frame(width: 100, height: 100)

            Image(systemName: iconName)
                .font(.system(size: 44))
                .foregroundColor(iconBackgroundColor)
        }
    }

    private var iconName: String {
        isOffline ? "wifi.slash" : "wifi.exclamationmark"
    }

    private var iconBackgroundColor: Color {
        isOffline ? .tidexTextMuted : .tidexWarning
    }

    // MARK: - Actions

    private func handleRetry() {
        isRetrying = true
        Task {
            await onRetry()
            isRetrying = false
        }
    }

    private func handleRestore() {
        isRestoring = true
        Task {
            await onRestore()
            isRestoring = false
        }
    }
}

// MARK: - Preview

#Preview("Offline") {
    VerificationRequiredView(
        isOffline: true,
        onRetry: {},
        onRestore: {}
    )
}

#Preview("Online") {
    VerificationRequiredView(
        isOffline: false,
        onRetry: {},
        onRestore: {}
    )
}
