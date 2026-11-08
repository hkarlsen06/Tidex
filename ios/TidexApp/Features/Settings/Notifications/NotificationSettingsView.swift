import SwiftUI
import UserNotifications

/// Notification settings view
/// Allows users to configure shift reminders and shared shift notifications
struct NotificationSettingsView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel = NotificationSettingsViewModel()

  var body: some View {
    Form {
      Group {
        systemPermissionSection
        shiftRemindersSection
        smartNotificationsSection
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
      .presentationDetents([.medium, .large])
    }
  }

  // MARK: - System Permission Section

  /// Only shown while notifications are off, since there is nothing to do once they are on.
  @ViewBuilder
  private var systemPermissionSection: some View {
    switch viewModel.notificationStatus {
    case .notDetermined:
      Section {
        permissionRow(icon: "bell.badge", iconColor: .tidexBlueText) {
          Button {
            Task {
              await viewModel.requestNotificationPermission()
            }
          } label: {
            Text(.notificationsPermissionEnable)
          }
          .buttonStyle(.borderedProminent)
        }
      }

    case .denied:
      Section {
        permissionRow(icon: "bell.slash.fill", iconColor: .tidexError) {
          Button {
            viewModel.openSystemSettings()
          } label: {
            Text(.notificationsPermissionOpenSettings)
          }
          .buttonStyle(.bordered)
          .tint(.tidexBlueText)
        }
      } footer: {
        Text(.notificationsPermissionDeniedHint)
      }

    default:
      EmptyView()
    }
  }

  private func permissionRow<Action: View>(
    icon: String,
    iconColor: Color,
    @ViewBuilder action: () -> Action
  ) -> some View {
    permissionRowLayout {
      Label {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(.notificationsPermissionTitle)
            .font(.tidexBodyMedium)
            .foregroundStyle(Color.tidexTextPrimary)

          Text(permissionStatusText)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
        }
      } icon: {
        Image(systemName: icon)
          .foregroundStyle(iconColor)
      }

      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: Spacing.xs)
      }

      action()
        .controlSize(.small)
        .tint(.tidexBlue)
    }
  }

  private var permissionRowLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
  }

  private var permissionStatusText: String {
    viewModel.notificationStatus == .denied
      ? String(localized: .notificationsPermissionDenied)
      : String(localized: .notificationsPermissionNotDetermined)
  }

  private var isPermissionDenied: Bool {
    viewModel.notificationStatus == .denied
  }

  // MARK: - Shift Reminders Section

  private var shiftRemindersSection: some View {
    Section {
      Toggle(isOn: $viewModel.shiftRemindersEnabled) {
        Text(String(localized: .notificationsRemindersSectionTitle))
      }
      .tint(.tidexBlue)

      if viewModel.shiftRemindersEnabled, !viewModel.reminderTimes.isEmpty {
        ForEach(Array(viewModel.reminderTimes.enumerated()), id: \.offset) { index, minutes in
          reminderTimeRow(minutes: minutes, index: index)
        }

        if viewModel.canAddReminder {
          addReminderButton
        }
      }
    } footer: {
      Text(.notificationsRemindersDescription)
    }
    .disabled(isPermissionDenied)
  }

  private func reminderTimeRow(minutes: Int, index: Int) -> some View {
    Button {
      viewModel.prepareForEditingTime(at: index)
    } label: {
      HStack(spacing: Spacing.sm) {
        Label {
          Text(viewModel.formatReminderTime(minutes, locale: Locale.current))
            .foregroundStyle(Color.tidexTextPrimary)
        } icon: {
          Image(systemName: "clock")
            .foregroundStyle(Color.tidexTextSecondary)
        }

        Spacer(minLength: Spacing.xs)

        Image(systemName: "chevron.right")
          .font(.tidexCaptionRegular)
          .foregroundStyle(Color.tidexTextMuted)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      SwipeDeleteButton(title: String(localized: .commonDelete)) {
        viewModel.deleteReminderTime(at: index)
      }
    }
  }

  private var addReminderButton: some View {
    Button {
      viewModel.prepareForAddingTime()
    } label: {
      Label {
        Text(.notificationsRemindersAddTime)
          .foregroundStyle(Color.tidexBlueText)
      } icon: {
        Image(systemName: "plus.circle.fill")
          .foregroundStyle(Color.tidexBlueText)
      }
    }
  }

  // MARK: - Smart Notifications Section

  private var smartNotificationsSection: some View {
    Section {
      Toggle(isOn: $viewModel.smartNotificationsEnabled) {
        Text(String(localized: .notificationsSmartSectionTitle))
      }
      .tint(.tidexBlue)
    } footer: {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(.notificationsSmartDescription)
        smartStatusText
      }
    }
    .disabled(isPermissionDenied)
  }

  @ViewBuilder
  private var smartStatusText: some View {
    switch viewModel.smartStatus {
    case .active(let scheduledCount, let workDays):
      Text(.notificationsSmartStatusActive(scheduledCount, workDays))
        .foregroundStyle(Color.tidexSuccess)

    case .insufficientData(let weeksFound, let weeksRequired):
      let weeksNeeded = weeksRequired - weeksFound
      Text(.notificationsSmartStatusInsufficientData(weeksNeeded, weeksFound, weeksRequired))
        .foregroundStyle(Color.tidexWarning)

    case .noShifts:
      Text(.notificationsSmartStatusNoShifts)
        .foregroundStyle(Color.tidexWarning)

    case .noPatternDetected:
      Text(.notificationsSmartStatusNoPattern)
        .foregroundStyle(Color.tidexWarning)

    case .disabled, .permissionDenied, nil:
      EmptyView()
    }
  }

  // MARK: - Shared Shifts Section

  private var sharedShiftsSection: some View {
    Section {
      Toggle(isOn: $viewModel.sharedShiftsEnabled) {
        Text(String(localized: .notificationsSharedSectionTitle))
      }
      .tint(.tidexBlue)
    } footer: {
      Text(.notificationsSharedDescription)
    }
    .disabled(isPermissionDenied)
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    NotificationSettingsView()
  }
}
