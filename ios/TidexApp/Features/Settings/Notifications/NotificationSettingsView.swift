import SwiftUI
import UserNotifications

/// Notification settings view
/// Allows users to configure shift reminders and shared shift notifications
struct NotificationSettingsView: View {
  @State private var viewModel = NotificationSettingsViewModel()

  var body: some View {
    Form {
      Group {
        // System permission section
        systemPermissionSection

        // Shift reminders section
        shiftRemindersSection

        // Smart notifications section
        smartNotificationsSection

        // Shared shifts section
        sharedShiftsSection
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .sensoryFeedback(.impact(weight: .light), trigger: viewModel.showTimePickerSheet) { _, new in
      new
    }
    .tidexListBackground()
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
      LabeledContent {
        permissionButton
      } label: {
        Label {
          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(.notificationsPermissionTitle)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(permissionStatusText)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        } icon: {
          Image(systemName: permissionIcon)
            .foregroundColor(permissionIconColor)
        }
      }
    } header: {
      Text(String(localized: .notificationsPermissionSectionTitle))
    } footer: {
      notificationPermissionFooter
    }
  }

  @ViewBuilder
  private var notificationPermissionFooter: some View {
    if viewModel.notificationStatus == .denied {
      Text(.notificationsPermissionDeniedHint)
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
          .padding(.vertical, Spacing.xxxs)
          .background(Color.tidexBlue.opacity(0.1))
          .cornerRadius(CornerRadius.xs)
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
          .foregroundColor(.tidexTextOnBrand)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xxxs)
          .background(Color.tidexBlue)
          .cornerRadius(CornerRadius.xs)
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
        Label {
          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(.notificationsRemindersTitle)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(.notificationsRemindersDescription)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        } icon: {
          Image(systemName: "bell.fill")
            .foregroundColor(.tidexBlue)
        }
      }
      .tint(.tidexBlue)

      // Reminder times (shown when enabled)
      if viewModel.shiftRemindersEnabled, !viewModel.reminderTimes.isEmpty {
        ForEach(Array(viewModel.reminderTimes.enumerated()), id: \.offset) { index, minutes in
          reminderTimeRow(minutes: minutes, index: index)
        }

        // Add button (if under max)
        if viewModel.canAddReminder {
          addReminderButton
        }
      }
    } header: {
      Text(String(localized: .notificationsRemindersSectionTitle))
    } footer: {
      Text(.notificationsRemindersSectionSubtitle)
    }
    .opacity(viewModel.notificationStatus == .denied ? 0.5 : 1.0)
    .disabled(viewModel.notificationStatus == .denied)
  }

  @ViewBuilder
  private func reminderTimeRow(minutes: Int, index: Int) -> some View {
    Button {
      viewModel.prepareForEditingTime(at: index)
    } label: {
      LabeledContent {
        Image(systemName: "pencil")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      } label: {
        Label {
          Text(viewModel.formatReminderTime(minutes, locale: Locale.current))
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextPrimary)
        } icon: {
          Image(systemName: "bell.fill")
            .font(.tidexBody)
            .foregroundColor(.tidexBlue)
        }
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var addReminderButton: some View {
    Button {
      viewModel.prepareForAddingTime()
    } label: {
      Label {
        Text(.notificationsRemindersAddTime)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
      } icon: {
        Image(systemName: "plus.circle.fill")
          .font(.tidexBody)
          .foregroundColor(.tidexBlue)
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Shared Shifts Section

  private var smartNotificationsSection: some View {
    Section {
      Toggle(isOn: $viewModel.smartNotificationsEnabled) {
        Label {
          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(.notificationsSmartTitle)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(.notificationsSmartDescription)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        } icon: {
          Image(systemName: "brain.head.profile")
            .foregroundColor(.tidexBlue)
        }
      }
      .tint(.tidexBlue)
    } header: {
      Text(String(localized: .notificationsSmartSectionTitle))
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
          .foregroundColor(.tidexWarning)

      case .noShifts:
        Text(.notificationsSmartStatusNoShifts)
          .foregroundColor(.tidexWarning)

      case .noPatternDetected:
        Text(.notificationsSmartStatusNoPattern)
          .foregroundColor(.tidexWarning)

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
        Label {
          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(.notificationsSharedTitle)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(.notificationsSharedDescription)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        } icon: {
          Image(systemName: "person.2.fill")
            .foregroundColor(.tidexBlue)
        }
      }
      .tint(.tidexBlue)
    } header: {
      Text(String(localized: .notificationsSharedSectionTitle))
    } footer: {
      Text(.notificationsSharedSectionSubtitle)
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
}
