import ActivityKit
import BackgroundTasks
import Capacitor
import FirebaseCore
import FirebaseMessaging
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

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Firebase BEFORE creating any windows
        FirebaseApp.configure()

        // Set messaging delegate
        Messaging.messaging().delegate = self

        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Register background task for shift checking (Live Activity auto-start)
        registerBackgroundTasks()

        return true
    }

    // MARK: - Background Tasks for Live Activity

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: shiftCheckTaskId, using: nil) { [weak self] task in
            self?.handleShiftCheckTask(task as! BGAppRefreshTask)
        }
    }

    /// Schedule the next shift check background task
    func scheduleShiftCheckTask() {
        let request = BGAppRefreshTaskRequest(identifier: shiftCheckTaskId)
        // Request to run in 15 minutes (iOS may delay this)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGTask] Shift check scheduled")
        } catch {
            print("[BGTask] Failed to schedule shift check: \(error)")
        }
    }

    private func handleShiftCheckTask(_ task: BGAppRefreshTask) {
        // Schedule the next check
        scheduleShiftCheckTask()

        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Check for ongoing shifts and start Live Activity if needed
        if #available(iOS 16.2, *) {
            checkAndStartLiveActivity { success in
                task.setTaskCompleted(success: success)
            }
        } else {
            task.setTaskCompleted(success: true)
        }
    }

    @available(iOS 16.2, *)
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
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
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

    @available(iOS 16.2, *)
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

        let attributes = ShiftActivityAttributes(
            shiftId: shift.shiftId,
            shiftDate: shift.shiftDate,
            startTime: shift.startTime,
            endTime: shift.endTime,
            hourlyWage: shift.hourlyWage,
            supplementRatePerHour: shift.supplementRatePerHour,
            totalGrossEstimate: shift.totalGrossEstimate,
            locale: shift.locale
        )

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
    /// This gives Capacitor's bridge time to finish coalescing operations
    func startBackgroundTask() {
        // End any existing task first
        endBackgroundTaskIfNeeded()

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "CapacitorCleanup") { [weak self] in
            // Expiration handler - called when iOS is about to terminate the task
            // We MUST end the task here to avoid the warning
            self?.endBackgroundTaskIfNeeded()
        }

        // Give the bridge a moment to flush pending operations, then end the task
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

    // MARK: - URL Handling (for non-scene apps, kept for backwards compatibility)

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url (pre-iOS 13 or non-scene)
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links (pre-iOS 13 or non-scene)
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // MARK: - Remote Notification Registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Pass APNs token to Firebase - it will exchange for FCM token
        Messaging.messaging().apnsToken = deviceToken
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // FCM token received/refreshed
        // The @capacitor-firebase/messaging plugin handles forwarding this to JS
        print("[FCM] Token received: \(fcmToken ?? "nil")")
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
        // The @capacitor-firebase/messaging plugin handles forwarding tap data to JS
        completionHandler()
    }
}
