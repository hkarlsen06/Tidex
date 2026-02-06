import os.log
import Supabase
import SwiftUI

private let logger = Logger(subsystem: "no.tidex.app", category: "SettingsView")

/// Settings main menu view
/// Displays a list of settings options matching the web app's settings navigation
struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
        @Environment(\.dismiss) private var dismiss

    /// Whether the current user is an admin
    @State private var isAdmin = false
    /// Whether sign out is in progress
    @State private var isSigningOut = false
    /// Whether global sign out is in progress
    @State private var isSigningOutGlobal = false
    /// Whether to show the global sign out confirmation alert
    @State private var showSignOutEverywhereAlert = false
    /// Navigation path for settings subviews
    @State private var navigationPath = NavigationPath()

    /// Settings navigation destinations
    enum SettingsDestination: Hashable {
        case profile
        case security
        case subscription
        case notifications
        case appearance
        case pay
        case recurringShifts
        case data
        case feedback
        case admin
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 0) {
                    // Menu items grouped by category
                    VStack(spacing: 24) {
                        // Account & Security group
                        SettingsMenuGroup(title: String(localized: .settingsGroupAccountSecurity)) {
                            SettingsMenuItem(
                                icon: "person.circle",
                                title: String(localized: .settingsMenuAccountLabel),
                                description: String(localized: .settingsMenuAccountDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.profile)
                                }
                            )

                            SettingsMenuItem(
                                icon: "lock.shield",
                                title: String(localized: .settingsMenuSecurityLabel),
                                description: String(localized: .settingsMenuSecurityDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.security)
                                }
                            )

                            SettingsMenuItem(
                                icon: "creditcard",
                                title: String(localized: .settingsMenuSubscriptionLabel),
                                description: String(localized: .settingsMenuSubscriptionDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.subscription)
                                }
                            )
                        }

                        // Preferences group
                        SettingsMenuGroup(title: String(localized: .settingsGroupPreferences)) {
                            SettingsMenuItem(
                                icon: "bell",
                                title: String(localized: .settingsMenuNotificationsLabel),
                                description: String(localized: .settingsMenuNotificationsDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.notifications)
                                }
                            )

                            SettingsMenuItem(
                                icon: "paintpalette",
                                title: String(localized: .settingsMenuAppearanceLabel),
                                description: String(localized: .settingsMenuAppearanceDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.appearance)
                                }
                            )
                        }

                        // App Settings group
                        SettingsMenuGroup(title: String(localized: .settingsGroupAppSettings)) {
                            SettingsMenuItem(
                                icon: "banknote",
                                title: String(localized: .settingsMenuPayLabel),
                                description: String(localized: .settingsMenuPayDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.pay)
                                }
                            )

                            SettingsMenuItem(
                                icon: "repeat.circle",
                                title: String(localized: .settingsMenuRecurringShiftsLabel),
                                description: String(localized: .settingsMenuRecurringShiftsDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.recurringShifts)
                                }
                            )
                        }

                        // Data & Support group
                        SettingsMenuGroup(title: String(localized: .settingsGroupDataSupport)) {
                            SettingsMenuItem(
                                icon: "externaldrive",
                                title: String(localized: .settingsMenuDataLabel),
                                description: String(localized: .settingsMenuDataDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.data)
                                }
                            )

                            SettingsMenuItem(
                                icon: "message",
                                title: String(localized: .settingsMenuFeedbackLabel),
                                description: String(localized: .settingsMenuFeedbackDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.feedback)
                                }
                            )
                        }

                        // Admin section (only visible for admins)
                        if isAdmin {
                            SettingsMenuGroup(title: String(localized: .settingsGroupAdmin)) {
                                SettingsMenuItem(
                                    icon: "shield.lefthalf.filled.badge.checkmark",
                                    title: String(localized: .settingsMenuAdminLabel),
                                    description: String(localized: .settingsMenuAdminDescription),
                                    iconColor: .tidexWarning,
                                    action: {
                                        navigationPath.append(SettingsDestination.admin)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Sign out buttons
                    VStack(spacing: 12) {
                        signOutButton
                        signOutEverywhereButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.tidexBackground)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(.settingsTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.tidexTextPrimary)

                        Text(.settingsSubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextSecondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.tidexTextMuted)
                    }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                Group {
                    switch destination {
                    case .profile:
                        ProfileSettingsView()
                    case .security:
                        SecuritySettingsView()
                    case .subscription:
                        SubscriptionSettingsView()
                    case .notifications:
                        NotificationSettingsView()
                    case .appearance:
                        AppearanceSettingsView()
                    case .pay:
                        PaySettingsView()
                    case .recurringShifts:
                        RecurringShiftsSettingsView()
                    case .data:
                        DataSettingsView()
                    case .feedback:
                        FeedbackSettingsView()
                    case .admin:
                        AdminSettingsView()
                    }
                }
                .toolbarRole(.editor)
            }
        }
        .task {
            await checkAdminStatus()
        }
        .alert(
            String(localized: .userMenuLogoutEverywhereConfirmTitle),
            isPresented: $showSignOutEverywhereAlert
        ) {
            Button(String(localized: .userMenuLogoutEverywhereConfirmCancel), role: .cancel) {}
            Button(String(localized: .userMenuLogoutEverywhereConfirmAction), role: .destructive) {
                Task {
                    await signOutGlobal()
                }
            }
        } message: {
            Text(.userMenuLogoutEverywhereConfirmDescription)
        }
    }

    // MARK: - Sign Out Buttons

    /// Sign out from this device only (local scope)
    private var signOutButton: some View {
        Button {
            Task {
                await signOut()
            }
        } label: {
            HStack(spacing: 12) {
                if isSigningOut {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .medium))
                }

                Text(isSigningOut
                     ? String(localized: .userMenuLoggingOut)
                     : String(localized: .userMenuLogout))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.buttonHeight)
            .background(Color.tidexError)
            .cornerRadius(12)
        }
        .disabled(isSigningOut || isSigningOutGlobal)
    }

    /// Sign out from ALL devices (global scope)
    private var signOutEverywhereButton: some View {
        Button {
            showSignOutEverywhereAlert = true
        } label: {
            HStack(spacing: 12) {
                if isSigningOutGlobal {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextSecondary))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .medium))
                }

                Text(isSigningOutGlobal
                     ? String(localized: .userMenuLogoutEverywhereLoading)
                     : String(localized: .userMenuLogoutEverywhere))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.tidexTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.buttonHeight)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.tidexBorder, lineWidth: 1)
            )
        }
        .disabled(isSigningOut || isSigningOutGlobal)
    }

    // MARK: - Actions

    private func checkAdminStatus() async {
        do {
            let session = try await AuthSessionManager.shared.getSession()
            // Check app_metadata for admin role
            // The role is stored in app_metadata which is set by the backend
            if let appMetadata = session.user.appMetadata["role"],
               case .string(let role) = appMetadata,
               role == "admin" {
                isAdmin = true
            }
        } catch {
            // Silently fail - non-admin is the default
            logger.debug("Could not check admin status: \(error.localizedDescription)")
        }
    }

    private func signOut() async {
        isSigningOut = true
        await coordinator.signOut()
        dismiss()
        isSigningOut = false
    }

    private func signOutGlobal() async {
        isSigningOutGlobal = true
        await coordinator.signOutGlobal()
        dismiss()
        isSigningOutGlobal = false
    }
}

// MARK: - Recurring Shifts Settings

private struct RecurringShiftsSettingsView: View {
    @State private var recurringShifts: [RecurringShiftRow] = []
    @State private var recurringShiftToEdit: RecurringShiftRow?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let impactHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else if recurringShifts.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(recurringShifts, id: \.id) { recurring in
                            recurringShiftRow(recurring)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .settingsRecurringShiftsTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRecurringShifts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
            Task {
                await loadRecurringShifts()
            }
        }
        .sheet(item: $recurringShiftToEdit) { recurring in
            RecurringShiftEditorSheet(
                recurringShift: recurring,
                onSave: { editResult in
                    recurringShiftToEdit = nil
                    Task {
                        await updateRecurringShift(editResult)
                    }
                },
                onDelete: {
                    let recurringId = recurring.id
                    recurringShiftToEdit = nil
                    Task {
                        await deleteRecurringShift(recurringId)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.settingsRecurringShiftsTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(.settingsRecurringShiftsSubtitle)
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(.settingsRecurringShiftsEmptyTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(.settingsRecurringShiftsEmptyDescription)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(12)
        .tidexCardShadow(cornerRadius: 12)
    }

    private func recurringShiftRow(_ recurring: RecurringShiftRow) -> some View {
        let exclusionCount = recurring.effectiveExclusions.count

        return Button {
            impactHaptic.impactOccurred()
            recurringShiftToEdit = recurring
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "\(recurring.cleanStartTime) - \(recurring.cleanEndTime)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                HStack(spacing: 6) {
                    Text(weekdaySummary(for: recurring.selected_days))
                    Text("•")
                    Text(repeatLabel(for: recurring.repeat_interval_weeks))
                    if exclusionCount > 0 {
                        Text("•")
                        Text(String(localized: .settingsRecurringShiftsExcludedCount(exclusionCount)))
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.tidexTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.tidexError)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.tidexError)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexError.opacity(0.1))
        )
    }

    private func loadRecurringShifts() async {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await AuthSessionManager.shared.getSession()
            let shifts = RecurringShiftsRepository.shared.getRecurringShifts(for: session.normalizedUserId)
            recurringShifts = sortRecurringShifts(shifts)
        } catch {
            logger.error("Failed to load recurring shifts settings: \(error.localizedDescription)")
            errorMessage = String(localized: .settingsRecurringShiftsLoadFailed)
        }

        isLoading = false
    }

    private func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
        do {
            _ = try await RecurringShiftsRepository.shared.updateRecurringShift(
                id: editResult.recurringId,
                startTime: editResult.startTime,
                endTime: editResult.endTime,
                repeatIntervalWeeks: editResult.repeatIntervalWeeks,
                selectedDays: editResult.selectedDays,
                endCondition: editResult.endCondition,
                exclusions: editResult.exclusions
            )

            await loadRecurringShifts()
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
        } catch {
            logger.error("Failed to update recurring shift from settings: \(error.localizedDescription)")
            errorMessage = String(localized: .settingsRecurringShiftsSaveFailed)
        }
    }

    private func deleteRecurringShift(_ recurringId: String) async {
        do {
            try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)
            await loadRecurringShifts()
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
        } catch {
            logger.error("Failed to delete recurring shift from settings: \(error.localizedDescription)")
            errorMessage = String(localized: .settingsRecurringShiftsDeleteFailed)
        }
    }

    private func sortRecurringShifts(_ shifts: [RecurringShiftRow]) -> [RecurringShiftRow] {
        shifts.sorted { lhs, rhs in
            let lhsEarliestAnchor = lhs.selected_days.values.min() ?? "9999-12-31"
            let rhsEarliestAnchor = rhs.selected_days.values.min() ?? "9999-12-31"
            if lhsEarliestAnchor != rhsEarliestAnchor {
                return lhsEarliestAnchor < rhsEarliestAnchor
            }
            if lhs.cleanStartTime != rhs.cleanStartTime {
                return lhs.cleanStartTime < rhs.cleanStartTime
            }
            return lhs.id < rhs.id
        }
    }

    private func weekdaySummary(for selectedDays: SelectedDays) -> String {
        let order = ["1", "2", "3", "4", "5", "6", "0"]
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: Locale.current.identifier)
        let symbols = calendar.shortWeekdaySymbols
        let labels = order
            .filter { selectedDays[$0] != nil }
            .compactMap { key -> String? in
                guard let index = Int(key), index >= 0, index < symbols.count else { return nil }
                return symbols[index]
            }
        return labels.joined(separator: ", ")
    }

    private func repeatLabel(for repeatInterval: Int) -> String {
        if repeatInterval == 0 {
            return String(localized: .addShiftEveryWeek)
        }
        return String(localized: .addShiftEveryNWeeks(repeatInterval + 1))
    }
}

// MARK: - Settings Menu Group

/// A group of settings menu items with a section header
struct SettingsMenuGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .padding(.horizontal, 4)

            // Menu items
            VStack(spacing: 8) {
                content()
            }
        }
    }
}

// MARK: - Settings Menu Item

/// A single settings menu item with icon, title, description, and chevron
struct SettingsMenuItem: View {
    let icon: String
    let title: String
    let description: String
    var iconColor: Color = .tidexBlue
    let action: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)

                // Title and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Chevron
                Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppCoordinator.shared)
}
