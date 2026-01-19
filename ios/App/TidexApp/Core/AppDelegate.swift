import ActivityKit
import BackgroundTasks
import Supabase
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

    private let apnsTokenDefaultsKey = "apns_device_token"
    private let apnsTokenRegisteredUserKey = "apns_device_token_registered_user"
    private let apnsTokenRegisteredValueKey = "apns_device_token_registered_value"

    private func shiftDateTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }

    private func minutes(from time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private func isCrossMidnight(startTime: String, endTime: String) -> Bool {
        guard let startMinutes = minutes(from: startTime),
              let endMinutes = minutes(from: endTime) else {
            return endTime < startTime
        }
        return endMinutes < startMinutes
    }

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
            let formatter = shiftDateTimeFormatter()
            print("[BGTask] Live Activity scheduled for \(formatter.string(from: scheduledTime))")
        } catch {
            print("[BGTask] Failed to schedule Live Activity task: \(error)")
        }
    }

    /// Parse a shift's start date/time into a Date object
    private func getShiftStartDate(_ shift: StoredShift) -> Date? {
        shiftDateTimeFormatter().date(from: "\(shift.shiftDate) \(shift.startTime)")
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
        let formatter = shiftDateTimeFormatter()

        guard let startDate = formatter.date(from: "\(shift.shiftDate) \(shift.startTime)") else {
            return false
        }

        var endDate = formatter.date(from: "\(shift.shiftDate) \(shift.endTime)") ?? startDate

        // Handle cross-midnight shifts
        if isCrossMidnight(startTime: shift.startTime, endTime: shift.endTime) {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }

        return date >= startDate && date < endDate
    }

    private func startLiveActivityForShift(_ shift: StoredShift) {
        let now = Date()
        let formatter = shiftDateTimeFormatter()

        guard let startDate = formatter.date(from: "\(shift.shiftDate) \(shift.startTime)") else {
            return
        }

        var endDate = formatter.date(from: "\(shift.shiftDate) \(shift.endTime)") ?? startDate
        if isCrossMidnight(startTime: shift.startTime, endTime: shift.endTime) {
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

        cacheAPNsToken(tokenString)

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

    /// Register APNs token via the web app API
    /// The API uses service role credentials to access the internal.push_devices table
    private func registerAPNsToken(_ token: String) async {
        do {
            // Get current user session for auth and user ID
            let session = try await supabase.auth.session
            let userId = session.user.id.uuidString.lowercased()
            let defaults = UserDefaults.standard

            // Skip if already registered for this user
            if !needsAPNsRegistration(token: token, userId: userId) {
                print("[APNs] Token already registered for user \(userId.prefix(8))")
                return
            }

            // Build API request
            let url = APIConfiguration.webAppBaseURL.appendingPathComponent("api/push-device")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

            // Build payload with device info
            var payload: [String: Any] = [
                "apnsToken": token,
                "platform": "ios"
            ]

            // Add device metadata
            let device = await UIDevice.current
            payload["deviceModel"] = await device.model
            if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                payload["appVersion"] = appVersion
            }
            // Use identifierForVendor as device ID for token rotation detection
            if let deviceId = await device.identifierForVendor?.uuidString {
                payload["deviceId"] = deviceId
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            // Make the API call
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[APNs] Invalid response type")
                return
            }

            if httpResponse.statusCode == 200 {
                // Success - cache the registration
                defaults.set(token, forKey: apnsTokenRegisteredValueKey)
                defaults.set(userId, forKey: apnsTokenRegisteredUserKey)
                print("[APNs] Token registered via API for user \(userId.prefix(8))")
            } else {
                // Log error response
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[APNs] API error (\(httpResponse.statusCode)): \(errorMessage)")
            }
        } catch {
            print("[APNs] Failed to register token: \(error)")
        }
    }

    private func cacheAPNsToken(_ token: String) {
        let defaults = UserDefaults.standard
        let existingToken = defaults.string(forKey: apnsTokenDefaultsKey)

        if existingToken != token {
            defaults.set(token, forKey: apnsTokenDefaultsKey)
            defaults.removeObject(forKey: apnsTokenRegisteredValueKey)
            defaults.removeObject(forKey: apnsTokenRegisteredUserKey)
        }
    }

    private func cachedAPNsToken() -> String? {
        UserDefaults.standard.string(forKey: apnsTokenDefaultsKey)
    }

    func registerCachedAPNsTokenIfNeeded() async {
        guard let token = cachedAPNsToken() else {
            return
        }

        await registerAPNsToken(token)
    }

    private func needsAPNsRegistration(token: String, userId: String) -> Bool {
        let defaults = UserDefaults.standard
        let lastToken = defaults.string(forKey: apnsTokenRegisteredValueKey)
        let lastUserId = defaults.string(forKey: apnsTokenRegisteredUserKey)
        return lastToken != token || lastUserId != userId
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
