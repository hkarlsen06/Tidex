import SwiftUI
import UserNotifications

/// Notification settings view
/// Allows users to configure shift reminders and shared shift notifications
struct NotificationSettingsView: View {
  @StateObject private var viewModel = NotificationSettingsViewModel()

  var body: some View {
    List {
      // System permission section
      systemPermissionSection

      // Shift reminders section
      shiftRemindersSection

      // Smart notifications section
      smartNotificationsSection

      // Shared shifts section
      sharedShiftsSection
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .notificationsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSettings()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
    ) { _ in
      // Refresh permission status when returning to app
      Task {
        await viewModel.checkNotificationStatus()
      }
    }
    .sheet(
      isPresented: $viewModel.showTimePickerSheet,
      onDismiss: {
        viewModel.handlePickerDismiss()
      }
    ) {
      ReminderTimePickerSheet(
        hours: $viewModel.pickerHours,
        minutes: $viewModel.pickerMinutes,
        isEditing: viewModel.editingTimeIndex != nil,
        onSave: {
          viewModel.savePickerTime()
        },
        onDelete: viewModel.editingTimeIndex != nil
          ? {
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

  // MARK: - System Permission Section

  private var systemPermissionSection: some View {
    Section {
      HStack(spacing: Spacing.sm) {
        // Icon
        settingsIcon(systemName: permissionIcon, color: permissionIconColor)

        // Content
        VStack(alignment: .leading, spacing: 2) {
          Text(.notificationsPermissionTitle)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)

          Text(permissionStatusText)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        // Action button
        permissionButton
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    } header: {
      Text(.notificationsPermissionSectionTitle)
    } footer: {
      if viewModel.notificationStatus == .denied {
        Text(.notificationsPermissionDeniedHint)
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
      return String(localized: .notificationsPermissionEnabled)
    case .denied:
      return String(localized: .notificationsPermissionDenied)
    case .notDetermined:
      return String(localized: .notificationsPermissionNotDetermined)
    @unknown default:
      return String(localized: .notificationsPermissionNotDetermined)
    }
  }

  @ViewBuilder
  private var permissionButton: some View {
    switch viewModel.notificationStatus {
    case .authorized, .provisional, .ephemeral:
      // Show checkmark
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "checkmark.circle.fill")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexSuccess)

        Text(.notificationsPermissionActive)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexSuccess)
      }

    case .denied:
      // Open settings button
      Button {
        viewModel.openSystemSettings()
      } label: {
        Text(.notificationsPermissionOpenSettings)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
          .padding(.horizontal, Spacing.sm)
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
        Text(.notificationsPermissionEnable)
          .font(.tidexLabel)
          .foregroundColor(.white)
          .padding(.horizontal, Spacing.sm)
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
    Section {
      // Enable toggle
      Toggle(isOn: $viewModel.shiftRemindersEnabled) {
        HStack(spacing: Spacing.sm) {
          settingsIcon(systemName: "bell.fill", color: .tidexBlue)

          VStack(alignment: .leading, spacing: 2) {
            Text(.notificationsRemindersTitle)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(.notificationsRemindersDescription)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        }
      }
      .tint(.tidexBlue)
      .listRowBackground(Color.tidexSurfacePrimary)

      // Reminder times (shown when enabled)
      if viewModel.shiftRemindersEnabled && !viewModel.reminderTimes.isEmpty {
        ForEach(Array(viewModel.reminderTimes.enumerated()), id: \.offset) { index, minutes in
          reminderTimeRow(minutes: minutes, index: index)
            .listRowBackground(Color.tidexSurfacePrimary)
        }

        // Add button (if under max)
        if viewModel.canAddReminder {
          addReminderButton
            .listRowBackground(Color.tidexSurfacePrimary)
        }
      }
    } header: {
      Text(.notificationsRemindersSectionTitle)
    } footer: {
      Text(.notificationsRemindersSectionSubtitle)
    }
    .opacity(viewModel.notificationStatus == .denied ? 0.5 : 1.0)
    .disabled(viewModel.notificationStatus == .denied)
  }

  @ViewBuilder
  private func reminderTimeRow(minutes: Int, index: Int) -> some View {
    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      viewModel.prepareForEditingTime(at: index)
    } label: {
      HStack(spacing: Spacing.sm) {
        // Bell icon
        Image(systemName: "bell.fill")
          .font(.tidexBody)
          .foregroundColor(.tidexBlue)
          .frame(width: 24)

        // Time label
        Text(viewModel.formatReminderTime(minutes, locale: Locale.current))
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Image(systemName: "pencil")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var addReminderButton: some View {
    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      viewModel.prepareForAddingTime()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "plus.circle.fill")
          .font(.tidexBody)
          .foregroundColor(.tidexBlue)

        Text(.notificationsRemindersAddTime)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Shared Shifts Section

  private var smartNotificationsSection: some View {
    Section {
      Toggle(isOn: $viewModel.smartNotificationsEnabled) {
        HStack(spacing: Spacing.sm) {
          settingsIcon(systemName: "brain.head.profile", color: .purple)

          VStack(alignment: .leading, spacing: 2) {
            Text(.notificationsSmartTitle)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(.notificationsSmartDescription)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        }
      }
      .tint(.tidexBlue)
      .listRowBackground(Color.tidexSurfacePrimary)
    } header: {
      Text(.notificationsSmartSectionTitle)
    } footer: {
      smartStatusFooter
    }
    .opacity(viewModel.notificationStatus == .denied ? 0.5 : 1.0)
    .disabled(viewModel.notificationStatus == .denied)
  }

  @ViewBuilder
  private var smartStatusFooter: some View {
    if let status = viewModel.smartStatus {
      switch status {
      case .active(let scheduledCount, let workDays):
        Text(.notificationsSmartStatusActive(scheduledCount, workDays))
          .foregroundColor(.tidexSuccess)
      case .insufficientData(let weeksFound, let weeksRequired):
        let weeksNeeded = weeksRequired - weeksFound
        Text(.notificationsSmartStatusInsufficientData(weeksNeeded, weeksFound, weeksRequired))
          .foregroundColor(.orange)
      case .noShifts:
        Text(.notificationsSmartStatusNoShifts)
          .foregroundColor(.orange)
      case .noPatternDetected:
        Text(.notificationsSmartStatusNoPattern)
          .foregroundColor(.orange)
      case .disabled, .permissionDenied:
        Text(.notificationsSmartSectionSubtitle)
      }
    } else {
      Text(.notificationsSmartSectionSubtitle)
    }
  }

  private var sharedShiftsSection: some View {
    Section {
      Toggle(isOn: $viewModel.sharedShiftsEnabled) {
        HStack(spacing: Spacing.sm) {
          settingsIcon(systemName: "person.2.fill", color: .green)

          VStack(alignment: .leading, spacing: 2) {
            Text(.notificationsSharedTitle)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(.notificationsSharedDescription)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        }
      }
      .tint(.tidexBlue)
      .listRowBackground(Color.tidexSurfacePrimary)
    } header: {
      Text(.notificationsSharedSectionTitle)
    } footer: {
      Text(.notificationsSharedSectionSubtitle)
    }
    .opacity(viewModel.notificationStatus == .denied ? 0.5 : 1.0)
    .disabled(viewModel.notificationStatus == .denied)
  }

  // MARK: - Settings Icon

  private func settingsIcon(systemName: String, color: Color) -> some View {
    Image(systemName: systemName)
      .font(.tidexFootnote)
      .foregroundColor(.white)
      .frame(width: 29, height: 29)
      .background(color.opacity(0.75))
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    NotificationSettingsView()
  }
}
