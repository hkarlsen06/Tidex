import SwiftUI

/// Reusable empty state view displayed when no shifts are found
/// Used across the dashboard and other shift-related screens
struct NoShiftsEmptyState: View {
    /// Optional action button configuration
    let actionButton: ActionButtonConfig?
    
    /// Optional subtitle text below the main message
    let subtitle: String?
    
    @Environment(\.localization) private var localization

    // MARK: - Initialization

    /// Initialize with optional customization
    /// - Parameters:
    ///   - actionButton: Optional button configuration (e.g., retry, create shift)
    ///   - subtitle: Optional subtitle text for additional context
    init(
        actionButton: ActionButtonConfig? = nil,
        subtitle: String? = nil
    ) {
        self.actionButton = actionButton
        self.subtitle = subtitle
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.tidexTextMuted)

            // Main message
            Text(localization.string("dashboard.noShifts"))
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            // Optional subtitle
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.tidexSubheadline)
                    .foregroundColor(.tidexTextMuted)
                    .multilineTextAlignment(.center)
            }

            // Optional action button
            if let actionButton = actionButton {
                Button(action: actionButton.action) {
                    Text(actionButton.label)
                        .font(.tidexLabel)
                        .foregroundColor(.tidexBlue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.tidexBlue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Action Button Configuration

extension NoShiftsEmptyState {
    /// Configuration for the optional action button
    struct ActionButtonConfig {
        let label: String
        let action: () -> Void

        /// Retry action button
        static func retry(action: @escaping () -> Void) -> ActionButtonConfig {
            ActionButtonConfig(label: "Retry", action: action)
        }

        /// Create shift action button
        static func createShift(action: @escaping () -> Void) -> ActionButtonConfig {
            ActionButtonConfig(label: "Create Shift", action: action)
        }

        /// Custom action button
        static func custom(label: String, action: @escaping () -> Void) -> ActionButtonConfig {
            ActionButtonConfig(label: label, action: action)
        }
    }
}

// MARK: - Convenience Initializers

extension NoShiftsEmptyState {
    /// Empty state with retry button
    static func withRetry(action: @escaping () -> Void) -> NoShiftsEmptyState {
        NoShiftsEmptyState(
            actionButton: .retry(action: action),
            subtitle: nil
        )
    }

    /// Empty state with create shift button
    static func withCreateShift(action: @escaping () -> Void) -> NoShiftsEmptyState {
        NoShiftsEmptyState(
            actionButton: .createShift(action: action),
            subtitle: nil
        )
    }

    /// Empty state without any action button
    static var noAction: NoShiftsEmptyState {
        NoShiftsEmptyState(actionButton: nil, subtitle: nil)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 32) {
        // With retry button
        NoShiftsEmptyState.withRetry(action: {})
            .background(Color.tidexBackground)

        Divider()

        // With create shift button
        NoShiftsEmptyState.withCreateShift(action: {})
            .background(Color.tidexBackground)

        Divider()

        // With subtitle
        NoShiftsEmptyState(
            actionButton: .retry(action: {}),
            subtitle: "Start by creating your first shift"
        )
        .background(Color.tidexBackground)

        Divider()

        // No action button
        NoShiftsEmptyState.noAction
            .background(Color.tidexBackground)
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}

