import ActivityKit
import BackgroundTasks
import os
import Supabase
import UIKit
import WatchConnectivity

private let launchLog = Logger(subsystem: "no.tidex.app", category: "Launch")

class AppDelegate: UIResponder, UIApplicationDelegate {

  // Track background task to ensure proper cleanup
  // This prevents "Background task still not ended after expiration handlers were called" warning
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  // App Group identifier for shared storage
  private let appGroupId = "group.no.tidex.app"

  // Background task identifier for shift checking
  private let shiftCheckTaskId = "no.tidex.app.shiftcheck"

  private let apnsTokenDefaultsKey = "apns_device_token"

  /// Prevents duplicate APNs registration calls while one is in flight
  private var apnsRegistrationInFlight = false

  private func shiftDateTimeFormatter() -> DateFormatter {
    FormatterCache.shiftDateTimeFormatter(timeZone: .current)
  }

  private func minutes(from time: String) -> Int? {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return nil }
    return parts[0] * 60 + parts[1]
  }

  private func isCrossMidnight(startTime: String, endTime: String) -> Bool {
    guard let startMinutes = minutes(from: startTime),
      let endMinutes = minutes(from: endTime)
    else {
      return endTime < startTime
    }
    return endMinutes < startMinutes
  }

  private func sharedUserDefaults() -> UserDefaults? {
    guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil
    else {
      return nil
    }
    return UserDefaults(suiteName: appGroupId)
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    launchLog.info("[Launch] AppDelegate.didFinishLaunching START")
    Task { @MainActor in
      AppWarmup.shared.start()
    }

    // Set notification center delegate
    UNUserNotificationCenter.current().delegate = self

    // Preload all feedback sounds
    Haptics.prepareSounds()

    // Clear expired images from cache (1-hour TTL)
    ImageCache.shared.clearExpired()

    // Register background task for shift checking (Live Activity auto-start)
    registerBackgroundTasks()

    // Schedule Live Activity for the next upcoming shift
    // Uses cached shift data from App Group storage (synced when app is used)
    scheduleNextShiftLiveActivity()

    // Check immediately if there's an ongoing shift that needs a Live Activity
    // This handles the case where app launches during a shift
    checkAndStartLiveActivityIfNeeded()

    // Activate Watch Connectivity for Apple Watch companion app
    WatchConnectivityManager.shared.activateSession()

    // Always register for remote notifications on launch
    // Ensures APNs token stays fresh (e.g., after TestFlight → App Store transition)
    application.registerForRemoteNotifications()

    launchLog.info("[Launch] AppDelegate.didFinishLaunching END")
    return true
  }

  // MARK: - Scene Configuration

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    launchLog.info("[Launch] AppDelegate.configurationForConnecting")
    let config = UISceneConfiguration(
      name: "Default Configuration", sessionRole: connectingSceneSession.role)
    config.delegateClass = SceneDelegate.self
    return config
  }

  // MARK: - Background Tasks for Live Activity

  private func registerBackgroundTasks() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: shiftCheckTaskId, using: nil) {
      [weak self] task in
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
      return
    }

    let now = Date()

    // Find the next shift start time that's in the future
    let nextShiftStart =
      shifts
      .compactMap { getShiftStartDate($0) }
      .filter { $0 > now }
      .min()

    guard let shiftStart = nextShiftStart else {
      return
    }

    // Schedule task for 1 minute AFTER the shift starts
    // This ensures isShiftOngoing() returns true when the task runs
    let scheduledTime = shiftStart.addingTimeInterval(60)

    let request = BGAppRefreshTaskRequest(identifier: shiftCheckTaskId)
    request.earliestBeginDate = scheduledTime

    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      print("[BGTask] Failed to schedule: \(error)")
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
    checkAndStartLiveActivityIfNeeded()
    completion(true)
  }

  /// Check if there's an ongoing shift and start a Live Activity if needed.
  /// Also ends any Live Activities for shifts that are no longer ongoing.
  /// This is called from:
  /// - Background task handler (when the scheduled task fires)
  /// - App foreground (when user opens the app)
  /// - App launch (in didFinishLaunchingWithOptions)
  /// - After widget storage update (when shifts are synced/edited)
  ///
  /// This ensures the Live Activity starts reliably, not just depending on BGTask timing.
  func checkAndStartLiveActivityIfNeeded() {
    // Check if Live Activities are enabled
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return
    }

    // First, end any Live Activities for shifts that are no longer ongoing
    endStaleActivities()

    // Check if there's already an active activity
    guard Activity<ShiftActivityAttributes>.activities.isEmpty else {
      return
    }

    // Read upcoming shifts from shared storage
    guard let userDefaults = sharedUserDefaults(),
      let shiftsJson = userDefaults.string(forKey: "upcoming_shifts"),
      let shiftsData = shiftsJson.data(using: .utf8)
    else {
      return
    }

    // Parse shifts and find ongoing one
    do {
      let shifts = try JSONDecoder().decode([StoredShift].self, from: shiftsData)
      let now = Date()

      // Find the ongoing shift without verbose per-shift logging
      if let ongoingShift = shifts.first(where: { isShiftOngoing($0, at: now) }) {
        print(
          "[LiveActivity] Starting activity for shift \(ongoingShift.shiftDate) \(ongoingShift.startTime)-\(ongoingShift.endTime)"
        )
        startLiveActivityForShift(ongoingShift)
      }
      // Silent when no ongoing shift - this is the normal case
    } catch {
      print("[LiveActivity] Failed to parse shifts: \(error)")
    }
  }

  /// End any Live Activities whose shifts are no longer ongoing.
  /// This handles cases where:
  /// - A shift was edited to change its time so it's no longer current
  /// - A shift was deleted
  /// - The shift has ended naturally
  private func endStaleActivities() {
    let activities = Activity<ShiftActivityAttributes>.activities
    guard !activities.isEmpty else { return }

    // Read current shifts from storage
    let currentShifts: [StoredShift]
    if let userDefaults = sharedUserDefaults(),
      let shiftsJson = userDefaults.string(forKey: "upcoming_shifts"),
      let shiftsData = shiftsJson.data(using: .utf8),
      let shifts = try? JSONDecoder().decode([StoredShift].self, from: shiftsData)
    {
      currentShifts = shifts
    } else {
      currentShifts = []
    }

    let now = Date()

    for activity in activities {
      let shiftId = activity.attributes.shiftId

      // Find the shift in current storage
      let matchingShift = currentShifts.first { $0.shiftId == shiftId }

      var shouldEnd = false
      var reason = ""

      if matchingShift == nil {
        // Shift was deleted
        shouldEnd = true
        reason = "shift was deleted"
      } else if let shift = matchingShift {
        // Shift exists - check if it's still ongoing
        if !isShiftOngoing(shift, at: now) {
          shouldEnd = true
          reason = "shift is no longer ongoing (edited or ended)"
        }
      }

      if shouldEnd {
        print("[LiveActivity] Ending activity for shift \(shiftId): \(reason)")
        Task {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      }
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

    // Calculate net amount if tax rate is configured
    let totalNetEstimate: Double? = shift.taxRate.map { taxRate in
      shift.totalGrossEstimate * (1.0 - taxRate)
    }

    // Include startDate and endDate for real-time SwiftUI timer updates
    let attributes = ShiftActivityAttributes(
      shiftId: shift.shiftId,
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      hourlyWage: shift.hourlyWage,
      supplementRatePerHour: shift.supplementRatePerHour,
      totalGrossEstimate: shift.totalGrossEstimate,
      totalNetEstimate: totalNetEstimate,
      currencySymbol: shift.currencySymbol ?? "kr",
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
    } catch {
      print("[LiveActivity] Failed to start: \(error)")
    }
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

    backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TidexCleanup") {
      [weak self] in
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
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Convert token to hex string for storage
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

    cacheAPNsToken(tokenString)

    // Store APNs token in Supabase.
    // Skip when biometric lock is active — supabase.auth.session triggers the SDK's
    // biometric prompt via withBiometrics(), which races with AppLockView's unlock flow.
    // The cached token will be registered after unlock via handleAppForeground().
    Task { @MainActor in
      guard !BiometricAuthService.shared.isLocked else { return }
      await registerAPNsToken(tokenString)
    }
  }

  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[APNs] Failed to register: \(error)")
    Task { @MainActor in
      PushNotificationManager.shared.apnsRegistrationFailed(error)
    }
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Handle silent push notifications if needed
    completionHandler(.newData)
  }

  /// Register APNs token via the web app API
  /// The API uses service role credentials to access the internal.push_devices table
  private func registerAPNsToken(_ token: String) async {
    // Prevent duplicate in-flight registrations
    guard !apnsRegistrationInFlight else { return }

    // Never register push tokens during admin impersonation — this would
    // associate the admin's physical device with the impersonated user,
    // causing the admin to receive the target user's notifications.
    let isImpersonating = await MainActor.run { ImpersonationManager.shared.isImpersonating }
    guard !isImpersonating else {
      print("[APNs] Skipping registration during impersonation")
      return
    }

    do {
      // Get current user session for auth and user ID
      let session = try await supabase.auth.session

      apnsRegistrationInFlight = true
      defer { apnsRegistrationInFlight = false }

      // Build API request
      let url = APIConfiguration.webAppBaseURL.appendingPathComponent("api/push-device")
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

      // Build payload with device info
      var payload: [String: Any] = [
        "apnsToken": token,
        "platform": "ios",
      ]

      // Add device metadata
      let (deviceModel, deviceId) = await MainActor.run {
        let device = UIDevice.current
        return (device.model, device.identifierForVendor?.uuidString)
      }
      payload["deviceModel"] = deviceModel
      if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
        payload["appVersion"] = appVersion
      }
      // Use identifierForVendor as device ID for token rotation detection
      if let deviceId = deviceId {
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
        await MainActor.run {
          PushNotificationManager.shared.registrationSucceeded()
        }
      } else {
        // Log error response
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        print("[APNs] API error (\(httpResponse.statusCode)): \(errorMessage)")
        await MainActor.run {
          PushNotificationManager.shared.serverRegistrationFailed(errorMessage)
        }
      }
    } catch {
      print("[APNs] Failed to register token: \(error)")
      await MainActor.run {
        PushNotificationManager.shared.serverRegistrationFailed(error.localizedDescription)
      }
    }
  }

  private func cacheAPNsToken(_ token: String) {
    UserDefaults.standard.set(token, forKey: apnsTokenDefaultsKey)
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
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
  // Handle notification when app is in foreground
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show banner even when app is in foreground
    completionHandler([.banner, .sound])
  }

  // Handle notification tap
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let type = userInfo["type"] as? String ?? ""

    // Handle smart notification taps (prompt to add shift)
    if type == "smart_prompt",
      let dateISO = userInfo["date"] as? String
    {
      Task { @MainActor in
        SharedMonthContext.shared.preselectedDate = dateISO
        AppCoordinator.shared.pendingDeepLink = .addShift
      }
    }
    // Handle shift reminder notification taps
    else if type == "shift_reminder",
      let shiftDate = userInfo["shift_date"] as? String
    {
      // Navigate to shifts view with the shift highlighted
      Task { @MainActor in
        AppCoordinator.shared.pendingDeepLink = .shifts(dates: [shiftDate], action: .highlight)
      }
    }
    // Handle shared shift notifications (created, updated, deleted)
    else if type.hasPrefix("shared_shift_") {
      // Extract owner_id (the friend who shared)
      let ownerId = userInfo["owner_id"] as? String

      // Parse changes array (new format with shift IDs for highlighting)
      var changes: [AppCoordinator.ShiftChange]?
      if let changesArray = userInfo["changes"] as? [[String: Any]] {
        changes = changesArray.compactMap { dict -> AppCoordinator.ShiftChange? in
          guard let shiftId = dict["shift_id"] as? String,
            let date = dict["date"] as? String,
            let op = dict["op"] as? String
          else {
            return nil
          }
          return AppCoordinator.ShiftChange(shiftId: shiftId, date: date, op: op)
        }
      }

      // Extract dates from changes array, falling back to legacy shift_dates field
      var dates: [String]?
      if let changes = changes, !changes.isEmpty {
        // Extract unique dates from ALL changes (including deleted - useful to see when they're not working)
        dates = Array(Set(changes.map(\.date)))
      } else if let datesArray = userInfo["shift_dates"] as? [String] {
        // Legacy format: APNs sends arrays as-is
        dates = datesArray
      } else if let datesString = userInfo["shift_dates"] as? String {
        // Legacy format: FCM sends comma-separated strings
        dates = datesString.components(separatedBy: ",").map {
          $0.trimmingCharacters(in: .whitespaces)
        }
      }

      // Navigate to sharing tab with the specific friend and shifts highlighted
      Task { @MainActor in
        AppCoordinator.shared.pendingDeepLink = .sharing(
          sharerId: ownerId, highlightDates: dates, changes: changes)
      }
    }
    // Handle share_started notification (someone started sharing with you)
    else if type == "share_started" {
      let ownerId = userInfo["owner_id"] as? String
      Task { @MainActor in
        AppCoordinator.shared.pendingDeepLink = .sharing(
          sharerId: ownerId, highlightDates: nil, changes: nil)
      }
    }
    // Handle feedback_responded notification (admin responded to user's feedback)
    else if type == "feedback_responded" {
      Task { @MainActor in
        AppCoordinator.shared.pendingDeepLink = .feedback
      }
    }
    // Handle feedback_submitted notification (user submitted feedback, admin notification)
    else if type == "feedback_submitted" {
      Task { @MainActor in
        AppCoordinator.shared.pendingDeepLink = .adminFeedback
      }
    }
    // Handle deeplink from admin broadcast or other notification types
    else if let deeplink = userInfo["deeplink"] as? String,
      let url = URL(string: deeplink)
    {
      Task { @MainActor in
        if url.scheme == "tidex" {
          // Internal deep link - pass to AppCoordinator
          AppCoordinator.shared.handleDeepLink(url)
        } else {
          // External URL (e.g., itms-apps://, https://) - open with system
          await UIApplication.shared.open(url)
        }
      }
    }

    completionHandler()
  }
}
