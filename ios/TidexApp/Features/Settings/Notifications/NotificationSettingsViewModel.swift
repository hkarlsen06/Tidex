import Foundation
import UIKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "NotificationSettingsViewModel")

/// ViewModel for notification settings
@MainActor
final class NotificationSettingsViewModel: ObservableObject {
  // MARK: - Published State

  /// System notification permission status
  @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

  /// Whether shift reminders are enabled
  @Published var shiftRemindersEnabled: Bool = false {
    didSet {
      if oldValue != shiftRemindersEnabled {
        handleRemindersToggleChange()
      }
    }
  }

  /// Reminder times in minutes (sorted descending)
  @Published var reminderTimes: [Int] = [] {
    didSet {
      if oldValue != reminderTimes {
        updateReminderTimes()
      }
    }
  }

  // MARK: - Time Picker State

  /// Whether the time picker sheet is shown
  @Published var showTimePickerSheet: Bool = false

  /// Index of time being edited (nil = adding new)
  @Published var editingTimeIndex: Int?

  /// Picker hours value (0-48)
  @Published var pickerHours: Int = 1

  /// Picker minutes value (0-59)
  @Published var pickerMinutes: Int = 0

  /// Tracks if add was triggered by toggling ON with empty list
  private var addingFromEmptyToggle: Bool = false

  /// Whether shared shift notifications are enabled
  @Published var sharedShiftsEnabled: Bool = true {
    didSet {
      if oldValue != sharedShiftsEnabled {
        updateSharedShifts()
      }
    }
  }

  /// Whether smart notifications are enabled
  @Published var smartNotificationsEnabled: Bool = true {
    didSet {
      if oldValue != smartNotificationsEnabled {
        updateSmartNotifications()
      }
    }
  }

  /// Current status of smart notifications
  @Published var smartStatus: SmartNotificationScheduler.Status?

  /// Loading state
  @Published var isLoading: Bool = false

  /// Error message
  @Published var errorMessage: String?

  // MARK: - Private Properties

  private let preferencesRepository = NotificationPreferencesRepository.shared
  private var userId: String?
  private var isInitialLoad = true

  // MARK: - Initialization

  init() {}

  // MARK: - Public Methods

  /// Load notification settings
  func loadSettings() async {
    isLoading = true
    clearMessages()

    // Get current user
    do {
      userId = try await AuthSessionManager.shared.getUserId()
    } catch {
      logger.error("Failed to get user session: \(error.localizedDescription)")
      isLoading = false
      return
    }

    guard let userId = userId else {
      isLoading = false
      return
    }

    // Check system notification status
    await checkNotificationStatus()

    // Load preferences from repository
    let preferences = preferencesRepository.getOrCreatePreferences(for: userId)

    // Update state without triggering saves
    isInitialLoad = true
    reminderTimes = preferences.shiftReminderMinutesArray.sorted(by: >)
    // Enable toggle only if there are reminder times
    shiftRemindersEnabled = preferences.shiftRemindersEnabled && !reminderTimes.isEmpty
    sharedShiftsEnabled = preferences.sharedShiftsEnabled
    smartNotificationsEnabled = preferences.smartNotificationsEnabled ?? true
    isInitialLoad = false

    // Load smart notification status
    smartStatus = await SmartNotificationScheduler.shared.getStatus(for: userId)

    isLoading = false
    logger.info("Loaded notification preferences")
  }

  /// Check system notification permission status
  func checkNotificationStatus() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    notificationStatus = settings.authorizationStatus
  }

  /// Request notification permission
  func requestNotificationPermission() async {
    let center = UNUserNotificationCenter.current()

    do {
      let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

      if granted {
        // Register for remote notifications
        await MainActor.run {
          UIApplication.shared.registerForRemoteNotifications()
        }
        logger.info("Notification permission granted")
      } else {
        logger.info("Notification permission denied")
      }

      // Refresh status
      await checkNotificationStatus()
    } catch {
      logger.error("Failed to request notification permission: \(error.localizedDescription)")
      errorMessage = "Could not request notification permission"
    }
  }

  /// Open system settings
  func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  /// Clear messages
  func clearMessages() {
    errorMessage = nil
  }

  // MARK: - Time Picker Methods

  /// Whether a new reminder can be added (max 4)
  var canAddReminder: Bool {
    reminderTimes.count < 4
  }

  /// Prepare picker for adding new time
  func prepareForAddingTime() {
    editingTimeIndex = nil
    pickerHours = 1
    pickerMinutes = 0
    showTimePickerSheet = true
  }

  /// Prepare picker for editing existing time
  func prepareForEditingTime(at index: Int) {
    guard index < reminderTimes.count else { return }
    let minutes = reminderTimes[index]
    editingTimeIndex = index
    pickerHours = minutes / 60
    pickerMinutes = minutes % 60
    showTimePickerSheet = true
  }

  /// Save time from picker
  func savePickerTime() {
    let totalMinutes = (pickerHours * 60) + pickerMinutes

    // Validate: must be at least 1 minute
    guard totalMinutes >= 1 else { return }

    if let index = editingTimeIndex {
      // Editing existing - check for duplicate (excluding current)
      var testArray = reminderTimes
      testArray.remove(at: index)
      guard !testArray.contains(totalMinutes) else {
        showTimePickerSheet = false
        return
      }
      reminderTimes[index] = totalMinutes
    } else {
      // Adding new - check for duplicate
      guard !reminderTimes.contains(totalMinutes) else {
        showTimePickerSheet = false
        return
      }
      reminderTimes.append(totalMinutes)
    }

    // Sort descending (largest first)
    reminderTimes.sort(by: >)

    // Clear the adding-from-empty flag since we successfully added
    addingFromEmptyToggle = false

    showTimePickerSheet = false
  }

  /// Delete time at index
  func deleteReminderTime(at index: Int) {
    guard index < reminderTimes.count else { return }
    reminderTimes.remove(at: index)

    // If no reminders left, turn off the toggle
    if reminderTimes.isEmpty {
      shiftRemindersEnabled = false
    }
  }

  /// Handle picker dismissal (cancel)
  func handlePickerDismiss() {
    // If we were adding from empty toggle and user cancelled, reset toggle
    if addingFromEmptyToggle && reminderTimes.isEmpty {
      // Use isInitialLoad to prevent triggering the auto-open picker again
      isInitialLoad = true
      shiftRemindersEnabled = false
      isInitialLoad = false
      addingFromEmptyToggle = false

      // Manually update the repository since we bypassed the didSet
      if let userId = userId {
        preferencesRepository.updatePreferences(
          for: userId,
          remindersEnabled: false
        )

        // Reschedule notifications
        Task {
          await ShiftReminderScheduler.shared.scheduleAllReminders(for: userId)
        }

        logger.info("Reset shift reminders toggle after picker cancel")
      }
    }
    showTimePickerSheet = false
  }

  /// Format minutes as localized human-readable string
  func formatReminderTime(_ minutes: Int, locale: Locale) -> String {
    let hours = minutes / 60
    let mins = minutes % 60

    if hours == 0 {
      // Minutes only
      return String(localized: .notificationReminderMinutesBefore(Int(mins)))
    } else if mins == 0 {
      // Hours only
      if hours == 24 {
        return String(localized: .notificationReminderOneDayBefore)
      } else if hours == 48 {
        return String(localized: .notificationReminderTwoDaysBefore)
      }
      return String(localized: .notificationReminderHoursBefore(Int(hours)))
    } else {
      // Mixed hours and minutes
      return
        "\(hours) \(String(localized: .commonHoursShort)) \(mins) \(String(localized: .commonMinutesShort)) \(String(localized: .commonBefore))"
    }
  }

  // MARK: - Private Methods

  /// Handle toggle change for reminders
  private func handleRemindersToggleChange() {
    guard !isInitialLoad else { return }

    // If turning ON with no reminders, auto-open the picker
    if shiftRemindersEnabled && reminderTimes.isEmpty {
      addingFromEmptyToggle = true
      prepareForAddingTime()
      return
    }

    // Otherwise, update the preference
    guard let userId = userId else { return }

    preferencesRepository.updatePreferences(
      for: userId,
      remindersEnabled: shiftRemindersEnabled
    )

    // Reschedule notifications
    Task {
      await ShiftReminderScheduler.shared.scheduleAllReminders(for: userId)
    }

    logger.info("Updated shift reminders: \(self.shiftRemindersEnabled)")
  }

  /// Update reminder times preference
  private func updateReminderTimes() {
    guard !isInitialLoad, let userId = userId else { return }

    let minutesArray = reminderTimes.sorted(by: >)

    preferencesRepository.updatePreferences(
      for: userId,
      remindersEnabled: !minutesArray.isEmpty,
      reminderMinutes: minutesArray
    )

    // Reschedule notifications
    Task {
      await ShiftReminderScheduler.shared.scheduleAllReminders(for: userId)
    }

    logger.info("Updated reminder times: \(minutesArray)")
  }

  /// Update shared shifts preference
  private func updateSharedShifts() {
    guard !isInitialLoad, let userId = userId else { return }

    preferencesRepository.updatePreferences(
      for: userId,
      sharedShiftsEnabled: sharedShiftsEnabled
    )

    logger.info("Updated shared shifts: \(self.sharedShiftsEnabled)")
  }

  /// Update smart notifications preference
  private func updateSmartNotifications() {
    guard !isInitialLoad, let userId = userId else { return }

    preferencesRepository.updatePreferences(
      for: userId,
      smartNotificationsEnabled: smartNotificationsEnabled
    )

    Task {
      if smartNotificationsEnabled {
        await SmartNotificationScheduler.shared.scheduleSmartNotifications(for: userId)
      } else {
        await SmartNotificationScheduler.shared.cancelAllSmartNotifications()
      }
      smartStatus = await SmartNotificationScheduler.shared.getStatus(for: userId)
    }

    logger.info("Updated smart notifications: \(self.smartNotificationsEnabled)")
  }
}
