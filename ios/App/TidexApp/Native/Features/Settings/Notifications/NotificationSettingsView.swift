import SwiftUI
import UserNotifications

/// Notification settings view
/// Allows users to configure shift reminders and shared shift notifications
struct NotificationSettingsView: View {
    @Environment(\.localization) private var localization
    @StateObject private var viewModel = NotificationSettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // System permission section
                systemPermissionSection

                // Shift reminders section
                shiftRemindersSection

                // Shared shifts section
                sharedShiftsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(localization.string("notifications.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
        .task {
            await viewModel.loadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh permission status when returning to app
            Task {
                await viewModel.checkNotificationStatus()
            }
        }
        .sheet(isPresented: $viewModel.showTimePickerSheet, onDismiss: {
            viewModel.handlePickerDismiss()
        }) {
            ReminderTimePickerSheet(
                hours: $viewModel.pickerHours,
                minutes: $viewModel.pickerMinutes,
                isEditing: viewModel.editingTimeIndex != nil,
                onSave: {
                    viewModel.savePickerTime()
                },
                onDelete: viewModel.editingTimeIndex != nil ? {
                    if let index = viewModel.editingTimeIndex {
                        viewModel.deleteReminderTime(at: index)
                    }
                    viewModel.showTimePickerSheet = false
                } : nil,
                onCancel: {
                    viewModel.showTimePickerSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.string("notifications.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("notifications.subtitle"))
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - System Permission Section

    private var systemPermissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(localization.string("notifications.permission.sectionTitle"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)

            // Permission card
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    // Icon
                    Image(systemName: permissionIcon)
                        .font(.system(size: 20))
                        .foregroundColor(permissionIconColor)
                        .frame(width: 32, height: 32)

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string("notifications.permission.title"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)

                        Text(permissionStatusText)
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                    }

                    Spacer()

                    // Action button
                    permissionButton
                }
                .padding(16)
            }
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)

            // Hint if denied
            if viewModel.notificationStatus == .denied {
                Text(localization.string("notifications.permission.deniedHint"))
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }
        }
    }

    private var permissionIcon: String {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell.badge.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined:
            return "bell"
        @unknown default:
            return "bell"
        }
    }

    private var permissionIconColor: Color {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return .tidexSuccess
        case .denied:
            return .tidexError
        case .notDetermined:
            return .tidexBlue
        @unknown default:
            return .tidexBlue
        }
    }

    private var permissionStatusText: String {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return localization.string("notifications.permission.enabled")
        case .denied:
            return localization.string("notifications.permission.denied")
        case .notDetermined:
            return localization.string("notifications.permission.notDetermined")
        @unknown default:
            return localization.string("notifications.permission.notDetermined")
        }
    }

    @ViewBuilder
    private var permissionButton: some View {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            // Show checkmark
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexSuccess)

                Text(localization.string("notifications.permission.active"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexSuccess)
            }

        case .denied:
            // Open settings button
            Button {
                viewModel.openSystemSettings()
            } label: {
                Text(localization.string("notifications.permission.openSettings"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.tidexBlue.opacity(0.1))
                    .cornerRadius(6)
            }

        case .notDetermined:
            // Enable button
            Button {
                Task {
                    await viewModel.requestNotificationPermission()
                }
            } label: {
                Text(localization.string("notifications.permission.enable"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.tidexBlue)
                    .cornerRadius(6)
            }

        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Shift Reminders Section

    private var shiftRemindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string("notifications.reminders.sectionTitle"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)

                Text(localization.string("notifications.reminders.sectionSubtitle"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            // Reminders card
            VStack(spacing: 0) {
                // Enable toggle
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.tidexBlue)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string("notifications.reminders.title"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("notifications.reminders.description"))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.shiftRemindersEnabled)
                        .labelsHidden()
                        .tint(.tidexBlue)
                }
                .padding(16)

                // Reminder times (shown when enabled)
                if viewModel.shiftRemindersEnabled && !viewModel.reminderTimes.isEmpty {
                    Divider()
                        .background(Color.tidexBorder)
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        // Reminder times list
                        VStack(spacing: 8) {
                            ForEach(Array(viewModel.reminderTimes.enumerated()), id: \.offset) { index, minutes in
                                reminderTimeRow(minutes: minutes, index: index)
                            }

                            // Add button (if under max)
                            if viewModel.canAddReminder {
                                addReminderButton
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
        .opacity(viewModel.notificationStatus == .denied ? 0.5 : 1.0)
        .disabled(viewModel.notificationStatus == .denied)
    }

    @ViewBuilder
    private func reminderTimeRow(minutes: Int, index: Int) -> some View {
        HStack(spacing: 12) {
            // Bell icon
            Image(systemName: "bell.fill")
                .font(.system(size: 16))
                .foregroundColor(.tidexBlue)
                .frame(width: 24)

            // Time label
            Text(viewModel.formatReminderTime(minutes, locale: localization.currentLocale))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextPrimary)

            Spacer()

            // Edit button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.prepareForEditingTime(at: index)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextMuted)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(10)
    }

    @ViewBuilder
    private var addReminderButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.prepareForAddingTime()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.tidexBlue)

                Text(localization.string("notifications.reminders.addTime"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(Color.tidexBlue.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Shifts Section

    private var sharedShiftsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string("notifications.shared.sectionTitle"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)

                Text(localization.string("notifications.shared.sectionSubtitle"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            // Shared shifts card
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.tidexBlue)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string("notifications.shared.title"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("notifications.shared.description"))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.sharedShiftsEnabled)
                        .labelsHidden()
                        .tint(.tidexBlue)
                }
                .padding(16)
            }
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
        .opacity(viewModel.notificationStatus == .denied ? 0.5 : 1.0)
        .disabled(viewModel.notificationStatus == .denied)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(\.localization, LocalizationManager.shared)
}
