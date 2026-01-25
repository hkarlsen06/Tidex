import SwiftUI

// MARK: - Month Limit Sheet

/// Sheet presented when free tier users try to add shifts to a new month
/// Offers two options: upgrade to Pro/Max, or delete shifts in other months
struct MonthLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localization) private var localization

    /// Existing months that have shifts (for display and deletion)
    let existingMonths: Set<DateComponents>

    /// Target month the user is trying to add shifts to
    let targetMonth: DateComponents

    /// Callback when user chooses to delete shifts in other months
    let onDeleteShifts: () async -> Bool

    /// Callback when deletion completes successfully and user wants to proceed
    let onDeleteComplete: () -> Void

    /// Callback when user upgrades successfully - auto-retry the action
    let onUpgradeComplete: () -> Void

    @State private var showPaywall = false
    @State private var tierBeforePaywall: SubscriptionTier = .free
    @State private var showDeleteSection = false
    @State private var showConfirmDelete = false
    @State private var isDeleting = false
    @State private var error: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full background
            Color.tidexBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero section with gradient
                    heroSection

                    // Content section
                    contentSection
                }
            }

            // Close button overlay
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .sheet(isPresented: $showPaywall, onDismiss: handlePaywallDismiss) {
            PaywallView(contextType: .monthLimit)
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack {
            // Gradient background extending to edges
            LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.45, blue: 0.95),
                    Color(red: 0.55, green: 0.35, blue: 0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative blurred circles
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: -120, y: -20)

            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(x: 130, y: 60)

            // Content
            VStack(spacing: 20) {
                Spacer()
                    .frame(height: 20)

                // Icon with glow effect
                ZStack {
                    // Glow
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 90, height: 90)
                        .blur(radius: 20)

                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                }

                // Title
                Text(AuthStrings.string("monthLimit.upgradeHeadline", locale: localization.currentLocale))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Subtitle
                Text(AuthStrings.string("monthLimit.upgradeSubheadline", locale: localization.currentLocale))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Spacer()
                    .frame(height: 24)
            }
            .padding(.horizontal, 32)
        }
        .frame(height: 280)
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: 28) {
            // Features list in a card
            featuresSection
                .padding(.top, 8)

            // Primary CTA - View Plans
            Button(action: {
                // Capture current tier before showing paywall
                tierBeforePaywall = EntitlementService.shared.effectiveTier
                showPaywall = true
            }) {
                HStack(spacing: 8) {
                    Text(AuthStrings.string("monthLimit.viewPlansButton", locale: localization.currentLocale))
                        .font(.system(size: 17, weight: .semibold))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 56)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.45, blue: 0.95),
                        Color(red: 0.55, green: 0.35, blue: 0.9)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(red: 0.45, green: 0.4, blue: 0.9).opacity(0.3), radius: 12, y: 6)
            .disabled(isDeleting)

            // Divider with "or"
            dividerWithOr

            // Delete section
            deleteSection
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 32)
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(spacing: 16) {
            featureRow(
                icon: "calendar.badge.plus",
                text: AuthStrings.string("monthLimit.feature1", locale: localization.currentLocale)
            )
            featureRow(
                icon: "chart.bar.fill",
                text: AuthStrings.string("monthLimit.feature2", locale: localization.currentLocale)
            )
            featureRow(
                icon: "square.and.arrow.up",
                text: AuthStrings.string("monthLimit.feature3", locale: localization.currentLocale)
            )
        }
        .padding(20)
        .background(Color.tidexSurfaceSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
        )
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.45, blue: 0.95),
                            Color(red: 0.55, green: 0.35, blue: 0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.tidexTextPrimary)

            Spacer()
        }
    }

    // MARK: - Divider

    private var dividerWithOr: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.tidexBorder.opacity(0.5))
                .frame(height: 1)

            Text(AuthStrings.string("monthLimit.or", locale: localization.currentLocale))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.tidexTextMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            Rectangle()
                .fill(Color.tidexBorder.opacity(0.5))
                .frame(height: 1)
        }
    }

    // MARK: - Delete Section

    @ViewBuilder
    private var deleteSection: some View {
        if !showDeleteSection {
            // Collapsed state - subtle text button
            Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteSection = true } }) {
                HStack(spacing: 6) {
                    Text(AuthStrings.string("monthLimit.deleteShiftsLink", locale: localization.currentLocale))
                        .font(.system(size: 15, weight: .medium))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.tidexTextMuted)
            }
            .disabled(isDeleting)
        } else {
            // Expanded delete section
            VStack(spacing: 16) {
                // Header with collapse button
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(Color.tidexTextMuted.opacity(0.1))
                            .frame(width: 40, height: 40)

                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.tidexTextMuted)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(AuthStrings.string("monthLimit.deleteTitle", locale: localization.currentLocale))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.tidexTextPrimary)

                        Text(deleteExplanationText)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tidexTextSecondary)
                            .lineSpacing(2)
                    }

                    Spacer()

                    // Collapse button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showDeleteSection = false
                            showConfirmDelete = false
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.tidexTextMuted)
                            .frame(width: 28, height: 28)
                            .background(Color.tidexTextMuted.opacity(0.1))
                            .clipShape(Circle())
                    }
                }

                if !showConfirmDelete {
                    // Initial delete button
                    Button(action: { withAnimation(.spring(response: 0.3)) { showConfirmDelete = true } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))

                            Text(AuthStrings.string("monthLimit.deleteButton", locale: localization.currentLocale))
                                .font(.system(size: 15, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 48)
                    .foregroundStyle(Color.tidexError)
                    .background(Color.tidexError.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.tidexError.opacity(0.2), lineWidth: 1)
                    )
                    .disabled(isDeleting)
                } else {
                    // Confirmation state
                    confirmDeleteSection
                }

                // Error display
                if let error = error {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tidexError)

                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.tidexError)
                    }
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tidexError.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(Spacing.md)
            .background(Color.tidexSurfaceSecondary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
            )
        }
    }

    // MARK: - Confirm Delete Section

    private var confirmDeleteSection: some View {
        VStack(spacing: Spacing.sm) {
            // Warning message
            HStack(alignment: .top, spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.tidexError)

                Text(confirmDeleteMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.tidexError)
                    .lineSpacing(2)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tidexError.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Action buttons
            HStack(spacing: Spacing.xs) {
                // Cancel
                Button(action: { withAnimation(.spring(response: 0.3)) { showConfirmDelete = false } }) {
                    Text(AuthStrings.string("monthLimit.cancelDelete", locale: localization.currentLocale))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 44)
                .foregroundStyle(Color.tidexTextSecondary)
                .background(Color.tidexSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isDeleting)

                // Confirm delete
                Button(action: handleDeleteConfirm) {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(confirmDeleteButtonText)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 44)
                .foregroundStyle(.white)
                .background(Color.tidexError)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isDeleting)
            }
        }
    }

    // MARK: - Computed Properties

    /// Months that will be deleted (existing months minus target month)
    private var monthsToDelete: [DateComponents] {
        existingMonths.filter { $0 != targetMonth }.sorted {
            guard let y1 = $0.year, let m1 = $0.month,
                  let y2 = $1.year, let m2 = $1.month else { return false }
            return (y1, m1) < (y2, m2)
        }
    }

    private var deleteCount: Int {
        monthsToDelete.count
    }

    private var formattedTargetMonth: String {
        formatMonth(targetMonth)
    }

    private var formattedOtherMonths: String {
        monthsToDelete.map { formatMonth($0) }.joined(separator: ", ")
    }

    private var deleteExplanationText: String {
        AuthStrings.string("monthLimit.deleteExplanation", locale: localization.currentLocale)
            .replacingOccurrences(of: "{targetMonth}", with: formattedTargetMonth)
            .replacingOccurrences(of: "{otherMonths}", with: formattedOtherMonths)
    }

    private var confirmDeleteMessage: String {
        AuthStrings.string("monthLimit.confirmDeleteMessage", locale: localization.currentLocale)
            .replacingOccurrences(of: "{months}", with: formattedOtherMonths)
    }

    private var confirmDeleteButtonText: String {
        if deleteCount == 1 {
            return AuthStrings.string("monthLimit.confirmDeleteButton", locale: localization.currentLocale)
                .replacingOccurrences(of: "{count}", with: "1")
        } else {
            return AuthStrings.string("monthLimit.confirmDeleteButtonPlural", locale: localization.currentLocale)
                .replacingOccurrences(of: "{count}", with: "\(deleteCount)")
        }
    }

    // MARK: - Helpers

    private func formatMonth(_ components: DateComponents) -> String {
        guard let year = components.year, let month = components.month else { return "" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localization.currentLocale == .norwegian ? "nb_NO" : "en_US")
        formatter.dateFormat = "MMMM yyyy"

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = 1

        guard let date = Calendar.current.date(from: dateComponents) else { return "" }
        return formatter.string(from: date)
    }

    // MARK: - Actions

    /// Called when paywall sheet dismisses - check if user upgraded
    private func handlePaywallDismiss() {
        let currentTier = EntitlementService.shared.effectiveTier

        // If tier changed from free to paid, user successfully upgraded
        if tierBeforePaywall == .free && currentTier != .free {
            // Dismiss this sheet and trigger the retry
            dismiss()
            onUpgradeComplete()
        }
    }

    private func handleDeleteConfirm() {
        isDeleting = true
        error = nil

        Task {
            let success = await onDeleteShifts()

            await MainActor.run {
                isDeleting = false

                if success {
                    // Dismiss sheet and notify parent
                    dismiss()
                    onDeleteComplete()
                } else {
                    error = AuthStrings.string("monthLimit.couldNotDeleteShifts", locale: localization.currentLocale)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MonthLimitSheet(
        existingMonths: [
            DateComponents(year: 2025, month: 1),
            DateComponents(year: 2025, month: 2)
        ],
        targetMonth: DateComponents(year: 2025, month: 3),
        onDeleteShifts: { true },
        onDeleteComplete: {},
        onUpgradeComplete: {}
    )
}
