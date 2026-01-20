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
    @Published var shiftRemindersEnabled: Bool = true {
        didSet {
            if oldValue != shiftRemindersEnabled {
                updateShiftReminders()
            }
        }
    }

    /// Selected reminder times in minutes
    @Published var selectedReminderMinutes: Set<Int> = [300] {
        didSet {
            if oldValue != selectedReminderMinutes {
                updateReminderTimes()
            }
        }
    }

    /// Whether shared shift notifications are enabled
    @Published var sharedShiftsEnabled: Bool = true {
        didSet {
            if oldValue != sharedShiftsEnabled {
                updateSharedShifts()
            }
        }
    }

    /// Loading state
    @Published var isLoading: Bool = false

    /// Error message
    @Published var errorMessage: String?

    /// Success message
    @Published var successMessage: String?

    // MARK: - Static Data

    /// Available reminder time options (in minutes)
    static let reminderOptions: [(minutes: Int, labelKey: String)] = [
        (60, "notifications.reminder.1hour"),
        (300, "notifications.reminder.5hours"),
        (1440, "notifications.reminder.1day")
    ]

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
            let session = try await supabase.auth.session
            userId = session.user.id.uuidString
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
        shiftRemindersEnabled = preferences.shiftRemindersEnabled
        selectedReminderMinutes = Set(preferences.shiftReminderMinutesArray)
        sharedShiftsEnabled = preferences.sharedShiftsEnabled
        isInitialLoad = false

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
        successMessage = nil
    }

    // MARK: - Private Methods

    /// Update shift reminders preference
    private func updateShiftReminders() {
        guard !isInitialLoad, let userId = userId else { return }

        preferencesRepository.updatePreferences(
            for: userId,
            remindersEnabled: shiftRemindersEnabled
        )

        // Reschedule notifications
        Task {
            await ShiftReminderScheduler.shared.scheduleAllReminders(for: userId)
        }

        // Trigger sync
        Task {
            await SyncCoordinator.shared.sync(reason: .localChange, userId: userId)
        }

        logger.info("Updated shift reminders: \(self.shiftRemindersEnabled)")
    }

    /// Update reminder times preference
    private func updateReminderTimes() {
        guard !isInitialLoad, let userId = userId else { return }

        // Ensure at least one time is selected
        if selectedReminderMinutes.isEmpty {
            selectedReminderMinutes = [300] // Default to 5 hours
            return
        }

        let minutesArray = Array(selectedReminderMinutes).sorted()

        preferencesRepository.updatePreferences(
            for: userId,
            reminderMinutes: minutesArray
        )

        // Reschedule notifications
        Task {
            await ShiftReminderScheduler.shared.scheduleAllReminders(for: userId)
        }

        // Trigger sync
        Task {
            await SyncCoordinator.shared.sync(reason: .localChange, userId: userId)
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

        // Trigger sync
        Task {
            await SyncCoordinator.shared.sync(reason: .localChange, userId: userId)
        }

        logger.info("Updated shared shifts: \(self.sharedShiftsEnabled)")
    }
}
