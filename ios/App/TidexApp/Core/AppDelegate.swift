import ActivityKit
import BackgroundTasks
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Track background task to ensure proper cleanup
    // This prevents "Background task still not ended after expiration handlers were called" warning
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // App Group identifier for shared storage
    private let appGroupId = "group.no.tidex.app"

    // Background task identifier for shift checking
    private let shiftCheckTaskId = "no.tidex.app.shiftcheck"

    private func sharedUserDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil else {
            return nil
        }
        return UserDefaults(suiteName: appGroupId)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Register background task for shift checking (Live Activity auto-start)
        registerBackgroundTasks()

        // Schedule Live Activity for the next upcoming shift
        // Uses cached shift data from App Group storage (synced when app is used)
        scheduleNextShiftLiveActivity()

        return true
    }

    // MARK: - Background Tasks for Live Activity

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: shiftCheckTaskId, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.handleShiftCheckTask(refreshTask)
        }
    }

    /// Schedule a background task to start a Live Activity when the next shift begins.
    ///
    /// This replaces the old 15-minute polling approach with targeted scheduling:
    /// - Reads cached shifts from App Group storage
    /// - Finds the next shift that hasn't started yet
    /// - Schedules ONE task for 1 minute after that shift's start time
    /// - When the task fires, it starts the Live Activity and schedules the next shift
    ///
    /// Note: BGTaskScheduler only allows one pending task per identifier,
    /// so we always schedule just the next upcoming shift.
    func scheduleNextShiftLiveActivity() {
        // Cancel any existing scheduled task first
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: shiftCheckTaskId)

        guard let userDefaults = sharedUserDefaults(),
              let shiftsJson = userDefaults.string(forKey: "upcoming_shifts"),
              let data = shiftsJson.data(using: .utf8),
              let shifts = try? JSONDecoder().decode([StoredShift].self, from: data)
        else {
            print("[BGTask] No cached shifts available for scheduling")
            return
        }

        let now = Date()

        // Find the next shift start time that's in the future
        let nextShiftStart = shifts
            .compactMap { getShiftStartDate($0) }
            .filter { $0 > now }
            .min()

        guard let shiftStart = nextShiftStart else {
            print("[BGTask] No upcoming shifts to schedule")
            return
        }

        // Schedule task for 1 minute AFTER the shift starts
        // This ensures isShiftOngoing() returns true when the task runs
        let scheduledTime = shiftStart.addingTimeInterval(60)

        let request = BGAppRefreshTaskRequest(identifier: shiftCheckTaskId)
        request.earliestBeginDate = scheduledTime

        do {
            try BGTaskScheduler.shared.submit(request)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            print("[BGTask] Live Activity scheduled for \(formatter.string(from: scheduledTime))")
        } catch {
            print("[BGTask] Failed to schedule Live Activity task: \(error)")
        }
    }

    /// Parse a shift's start date/time into a Date object
    private func getShiftStartDate(_ shift: StoredShift) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: "\(shift.shiftDate) \(shift.startTime)")
    }

    private func handleShiftCheckTask(_ task: BGAppRefreshTask) {
        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Check for ongoing shifts and start Live Activity if needed
        checkAndStartLiveActivity { [weak self] success in
            task.setTaskCompleted(success: success)
            // Schedule the next shift's Live Activity
            self?.scheduleNextShiftLiveActivity()
        }
    }

    private func checkAndStartLiveActivity(completion: @escaping (Bool) -> Void) {
        // Check if Live Activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            completion(true)
            return
        }

        // Check if there's already an active activity
        guard Activity<ShiftActivityAttributes>.activities.isEmpty else {
            completion(true)
            return
        }

        // Read upcoming shifts from shared storage
        guard let userDefaults = sharedUserDefaults(),
              let shiftsJson = userDefaults.string(forKey: "upcoming_shifts"),
              let shiftsData = shiftsJson.data(using: .utf8) else {
            completion(true)
            return
        }

        // Parse shifts and find ongoing one
        do {
            let shifts = try JSONDecoder().decode([StoredShift].self, from: shiftsData)
            let now = Date()

            for shift in shifts {
                if isShiftOngoing(shift, at: now) {
                    // Start Live Activity for this shift
                    startLiveActivityForShift(shift)
                    break
                }
            }
            completion(true)
        } catch {
            print("[BGTask] Failed to parse shifts: \(error)")
            completion(false)
        }
    }

    private func isShiftOngoing(_ shift: StoredShift, at date: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current

        guard let startDate = formatter.date(from: "\(shift.shiftDate) \(shift.startTime)") else {
            return false
        }

        var endDate = formatter.date(from: "\(shift.shiftDate) \(shift.endTime)") ?? startDate

        // Handle cross-midnight shifts
        if shift.endTime < shift.startTime {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }

        return date >= startDate && date < endDate
    }

    private func startLiveActivityForShift(_ shift: StoredShift) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current

        guard let startDate = formatter.date(from: "\(shift.shiftDate) \(shift.startTime)") else {
            return
        }

        var endDate = formatter.date(from: "\(shift.shiftDate) \(shift.endTime)") ?? startDate
        if shift.endTime < shift.startTime {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }

        let elapsed = now.timeIntervalSince(startDate)
        let total = endDate.timeIntervalSince(startDate)
        let progress = min(100, max(0, (elapsed / total) * 100))
        let hoursWorked = elapsed / 3600
        let totalRate = shift.hourlyWage + shift.supplementRatePerHour
        let earnings = hoursWorked * totalRate
        let remainingMinutes = max(0, Int((total - elapsed) / 60))

        // Include startDate and endDate for real-time SwiftUI timer updates
        let attributes = ShiftActivityAttributes(
            shiftId: shift.shiftId,
            shiftDate: shift.shiftDate,
            startTime: shift.startTime,
            endTime: shift.endTime,
            hourlyWage: shift.hourlyWage,
            supplementRatePerHour: shift.supplementRatePerHour,
            totalGrossEstimate: shift.totalGrossEstimate,
            locale: shift.locale,
            startDate: startDate,
            endDate: endDate
        )

        // Initial state values are now fallback - the UI calculates real-time values
        let initialState = ShiftActivityAttributes.ContentState(
            currentEarnings: earnings,
            remainingMinutes: remainingMinutes,
            progressPercent: progress
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            print("[BGTask] Started Live Activity for shift \(shift.shiftId)")
        } catch {
            print("[BGTask] Failed to start Live Activity: \(error)")
        }
    }

    // MARK: - UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate.
        endBackgroundTaskIfNeeded()
    }

    // MARK: - Background Task Management

    /// Starts a background task with a proper expiration handler
    /// This gives background operations time to finish
    func startBackgroundTask() {
        // End any existing task first
        endBackgroundTaskIfNeeded()

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TidexCleanup") { [weak self] in
            // Expiration handler - called when iOS is about to terminate the task
            // We MUST end the task here to avoid the warning
            self?.endBackgroundTaskIfNeeded()
        }

        // Give a moment to flush pending operations, then end the task
        // This prevents the task from running indefinitely
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }

    /// Ends any active background task to prevent iOS termination warning
    func endBackgroundTaskIfNeeded() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Remote Notification Registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to hex string for storage
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[APNs] Token received: \(tokenString)")

        // Store APNs token in Supabase
        Task {
            await registerAPNsToken(tokenString)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Failed to register: \(error)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle silent push notifications if needed
        completionHandler(.newData)
    }

    /// Register APNs token with Supabase backend
    private func registerAPNsToken(_ token: String) async {
        do {
            // Get current user session
            let session = try await supabase.auth.session

            // Update existing device record with APNs token
            // This preserves the fcm_token for backwards compatibility during migration
            try await supabase
                .schema("internal")
                .from("push_devices")
                .update([
                    "apns_token": token,
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("user_id", value: session.user.id.uuidString)
                .execute()

            print("[APNs] Token registered with Supabase")
        } catch {
            print("[APNs] Failed to register token: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner even when app is in foreground
        completionHandler([.banner, .sound])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap navigation here if needed
        completionHandler()
    }
}
