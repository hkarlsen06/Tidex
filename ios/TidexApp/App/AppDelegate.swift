import ActivityKit
import Sentry
import UIKit
import os

private let launchLog = Logger(subsystem: "no.tidex.app", category: "Launch")

class AppDelegate: UIResponder, UIApplicationDelegate {
  /// Stable reference for flows where `UIApplication.shared.delegate` is wrapped by runtime internals.
  static weak var shared: AppDelegate?

  // Track background task to ensure proper cleanup
  // This prevents "Background task still not ended after expiration handlers were called" warning
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  // App Group identifier for shared storage
  private let appGroupId = "group.no.tidex.app"

  private let apnsTokenDefaultsKey = "apns_device_token"

  /// Prevents duplicate APNs registration calls while one is in flight
  private var apnsRegistrationInFlight = false
  /// Collapses rapid foreground/sync/auth triggers into one serialized maintenance run.
  private var liveActivityMaintenanceInFlight = false
  private var liveActivityMaintenancePending = false

  override init() {
    super.init()
    Self.shared = self
  }

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

  private func isTemporaryClockActivity(_ attributes: ShiftActivityAttributes) -> Bool {
    if let explicitFlag = attributes.isTemporaryClock {
      return explicitFlag
    }

    // Legacy fallback for activities created before the explicit marker existed.
    return attributes.endTime == "00:00"
      && attributes.totalGrossEstimate == 0
      && attributes.hourlyWage == 0
      && attributes.supplementRatePerHour == 0
  }

  private func doublesMatch(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.01) -> Bool {
    abs(lhs - rhs) <= tolerance
  }

  private func optionalDoublesMatch(_ lhs: Double?, _ rhs: Double?, tolerance: Double = 0.01)
    -> Bool
  {
    switch (lhs, rhs) {
    case (nil, nil):
      return true
    case (let lhsValue?, let rhsValue?):
      return doublesMatch(lhsValue, rhsValue, tolerance: tolerance)
    default:
      return false
    }
  }

  private func hasTemporaryClockSession(shiftId: String) -> Bool {
    let defaults = UserDefaults.standard
    let sessionKeyPrefix = "dashboard.clock.temporary-session."

    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(sessionKeyPrefix) {
      guard
        let data = defaults.data(forKey: key),
        let session = try? JSONDecoder().decode(TemporaryClockSession.self, from: data)
      else {
        continue
      }

      if session.id == shiftId {
        return true
      }
    }

    return false
  }

  private func isTerminalLiveActivityState(_ state: ActivityState) -> Bool {
    switch state {
    case .ended, .dismissed:
      return true
    default:
      return false
    }
  }

  private func nonTerminalLiveActivities() -> [Activity<ShiftActivityAttributes>] {
    Activity<ShiftActivityAttributes>.activities.filter {
      !isTerminalLiveActivityState($0.activityState)
    }
  }

  @MainActor
  private func waitForLiveActivityListToClear(
    maxAttempts: Int = 4,
    delayNanoseconds: UInt64 = 300_000_000
  ) async -> Bool {
    for attempt in 0..<maxAttempts {
      if nonTerminalLiveActivities().isEmpty {
        return true
      }

      // Wait for ActivityKit to clear ended activities from its in-memory list.
      guard attempt < maxAttempts - 1 else { break }
      try? await Task.sleep(nanoseconds: delayNanoseconds)
    }

    return nonTerminalLiveActivities().isEmpty
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

    if let sentryDSN = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
      !sentryDSN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      SentrySDK.start { options in
        options.dsn = sentryDSN
        options.debug = false
        #if DEBUG
          // Allow Session Replay while developing in environments Sentry marks as unreliable.
          options.experimental.enableSessionReplayInUnreliableEnvironment = true
        #endif
      }
      launchLog.info("[Launch] Sentry initialized")
    } else {
      launchLog.info("[Launch] Sentry not initialized (missing SENTRY_DSN)")
    }

    // --- Synchronous (must complete before launch finishes) ---

    // Must be set before any notifications arrive
    UNUserNotificationCenter.current().delegate = self

    // Apple recommends activating WCSession early in launch
    WatchConnectivityManager.shared.activateSession()

    // Prewarm the cached theme before SwiftUI builds the first frame.
    _ = AppearanceManager.shared

    // Prewarm coordinator so auth listener starts before RootContent is created.
    _ = AppCoordinator.shared

    // Trivial async system call
    application.registerForRemoteNotifications()

    // --- Deferred (fire-and-forget, never blocks launch or first frame) ---

    Task { @MainActor [weak self] in
      Haptics.prepareSounds()
      ImageCache.shared.clearExpired()
      self?.checkAndStartLiveActivityIfNeeded()
    }

    launchLog.info("[Launch] AppDelegate.didFinishLaunching END")
    return true
  }

  // WARNING: Do NOT override configurationForConnecting to set a custom UIWindowSceneDelegate.
  // In a SwiftUI @main App lifecycle, SwiftUI manages window creation via its own internal
  // scene delegate. Setting a custom delegateClass replaces it, and if that delegate doesn't
  // fully manage the window, SwiftUI's fallback is unreliable — causing a permanent black
  // screen on launch.

  /// Check if there's an ongoing shift and start a Live Activity if needed.
  /// Also ends any Live Activities for shifts that are no longer ongoing.
  /// This is called from:
  /// - App foreground (when user opens the app)
  /// - App launch (in didFinishLaunchingWithOptions)
  /// - After widget storage update (when shifts are synced/edited)
  ///
  /// This ensures the Live Activity starts whenever the app is active and data is refreshed.
  func checkAndStartLiveActivityIfNeeded() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      if self.liveActivityMaintenanceInFlight {
        self.liveActivityMaintenancePending = true
        return
      }

      self.liveActivityMaintenanceInFlight = true
      repeat {
        self.liveActivityMaintenancePending = false
        await self.performLiveActivityMaintenance()
      } while self.liveActivityMaintenancePending
      self.liveActivityMaintenanceInFlight = false
    }
  }

  @MainActor
  private func performLiveActivityMaintenance() async {
    // Check if Live Activities are enabled
    let authInfo = ActivityAuthorizationInfo()
    guard authInfo.areActivitiesEnabled else {
      return
    }

    // First, end any Live Activities for shifts that are no longer ongoing
    let endedAnyStaleActivities = await endStaleActivities()

    // Check if there's already an active activity
    let remainingActivities = Activity<ShiftActivityAttributes>.activities.filter {
      !isTerminalLiveActivityState($0.activityState)
    }
    guard remainingActivities.isEmpty else {
      // Some ended activities can persist briefly in ActivityKit's in-memory list.
      // Queue one more pass so we can start the replacement activity once the list clears.
      if endedAnyStaleActivities {
        liveActivityMaintenancePending = true
        Task { [weak self] in
          try? await Task.sleep(nanoseconds: 300_000_000)
          self?.checkAndStartLiveActivityIfNeeded()
        }
      }
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
        startLiveActivityForShift(ongoingShift)
      }
      // Silent when no ongoing shift - this is the normal case
    } catch {}
  }

  /// End any Live Activities whose shifts are no longer ongoing.
  /// This handles cases where:
  /// - A shift was edited to change its time so it's no longer current
  /// - A shift was deleted
  /// - The shift has ended naturally
  @MainActor
  private func endStaleActivities() async -> Bool {
    let activities = Activity<ShiftActivityAttributes>.activities.filter {
      !isTerminalLiveActivityState($0.activityState)
    }
    guard !activities.isEmpty else { return false }

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
    var endedAny = false

    for activity in activities {
      let shiftId = activity.attributes.shiftId

      // Find the shift in current storage
      let matchingShift = currentShifts.first { $0.shiftId == shiftId }

      var shouldEnd = false
      if matchingShift == nil {
        if isTemporaryClockActivity(activity.attributes) {
          if hasTemporaryClockSession(shiftId: shiftId) {
            // Temporary clock sessions are local-only and not part of upcoming_shifts.
            // Keep the activity alive until explicit cancel/commit/handoff logic ends it.
            continue
          }
          // Temporary activity has no backing local session anymore (e.g., after sign-out/reset).
          shouldEnd = true
        } else {
          // Shift was deleted
          shouldEnd = true
        }
      } else if let shift = matchingShift {
        // Shift exists - check if it's still ongoing
        if !isShiftOngoing(shift, at: now) {
          shouldEnd = true
        } else if shouldReplaceActivity(activity, with: shift) {
          shouldEnd = true
        }
      }

      if shouldEnd {
        endedAny = true
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }

    return endedAny
  }

  /// Immediately end any active Live Activity for the specified shift.
  /// Used when a shift is manually ended from the UI.
  func endLiveActivity(for shiftId: String) {
    Task { @MainActor [weak self] in
      let matchingActivities = Activity<ShiftActivityAttributes>.activities.filter {
        $0.attributes.shiftId == shiftId
      }
      guard !matchingActivities.isEmpty else { return }

      for activity in matchingActivities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }

      // Re-check immediately so replacement activities can start without waiting
      // for another foreground/sync trigger.
      self?.checkAndStartLiveActivityIfNeeded()
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: 300_000_000)
        self?.checkAndStartLiveActivityIfNeeded()
      }
    }
  }

  @MainActor
  func endAllLiveActivities(reason _: String = "user context changed") async {
    let activities = Activity<ShiftActivityAttributes>.activities
    guard !activities.isEmpty else { return }

    for activity in activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }

    liveActivityMaintenancePending = false
  }

  /// Start a temporary open-ended clock Live Activity.
  /// Uses `startDate` as both start and timer anchor so the Live Activity timer counts up.
  @MainActor
  func startTemporaryLiveActivity(
    shiftId: String,
    startedAt: Date,
    currencySymbol: String? = "kr"
  ) async {
    let authInfo = ActivityAuthorizationInfo()
    guard authInfo.areActivitiesEnabled else {
      return
    }

    // Ensure stale/previous activities do not block starting a fresh temporary clock activity.
    await endAllLiveActivities(reason: "starting temporary clock activity")
    guard await waitForLiveActivityListToClear() else {
      return
    }

    let isoDate = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone).string(
      from: startedAt)
    let timeFormatter = DateFormatter()
    timeFormatter.calendar = Calendar(identifier: .gregorian)
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.timeZone = Date.localTimeZone
    timeFormatter.dateFormat = "HH:mm"
    let startTime = timeFormatter.string(from: startedAt)

    let attributes = ShiftActivityAttributes(
      shiftId: shiftId,
      shiftDate: isoDate,
      startTime: startTime,
      endTime: "00:00",
      hourlyWage: 0,
      supplementRatePerHour: 0,
      totalGrossEstimate: 0,
      totalNetEstimate: nil,
      currencySymbol: currencySymbol ?? "kr",
      isTemporaryClock: true,
      startDate: startedAt,
      endDate: startedAt
    )

    let initialState = ShiftActivityAttributes.ContentState(
      currentEarnings: 0,
      remainingMinutes: 0,
      progressPercent: 0
    )

    let maxAttempts = 3
    for attempt in 1...maxAttempts {
      do {
        _ = try Activity.request(
          attributes: attributes,
          content: .init(state: initialState, staleDate: nil),
          pushType: nil
        )
        return
      } catch {
        guard attempt < maxAttempts else {
          return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
      }
    }
  }

  private func isShiftOngoing(_ shift: StoredShift, at date: Date) -> Bool {
    guard let range = shiftDateRange(for: shift) else { return false }
    return date >= range.startDate && date < range.endDate
  }

  private func shiftDateRange(for shift: StoredShift) -> (startDate: Date, endDate: Date)? {
    let formatter = shiftDateTimeFormatter()

    guard let startDate = formatter.date(from: "\(shift.shiftDate) \(shift.startTime)") else {
      return nil
    }

    var endDate = formatter.date(from: "\(shift.shiftDate) \(shift.endTime)") ?? startDate
    if isCrossMidnight(startTime: shift.startTime, endTime: shift.endTime) {
      endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
    }

    return (startDate: startDate, endDate: endDate)
  }

  private func shiftTotalNetEstimate(_ shift: StoredShift) -> Double? {
    shift.taxRate.map { taxRate in
      shift.totalGrossEstimate * (1.0 - taxRate)
    }
  }

  private func shouldReplaceActivity(
    _ activity: Activity<ShiftActivityAttributes>,
    with shift: StoredShift
  ) -> Bool {
    guard let range = shiftDateRange(for: shift) else { return false }

    let attributes = activity.attributes
    let expectedNetEstimate = shiftTotalNetEstimate(shift)
    let expectedCurrency = shift.currencySymbol ?? "kr"
    let currentCurrency = attributes.currencySymbol ?? "kr"

    return attributes.shiftDate != shift.shiftDate
      || attributes.startTime != shift.startTime
      || attributes.endTime != shift.endTime
      || !doublesMatch(attributes.hourlyWage, shift.hourlyWage)
      || !doublesMatch(attributes.supplementRatePerHour, shift.supplementRatePerHour)
      || !doublesMatch(attributes.totalGrossEstimate, shift.totalGrossEstimate)
      || !optionalDoublesMatch(attributes.totalNetEstimate, expectedNetEstimate)
      || currentCurrency != expectedCurrency
      || abs(attributes.startDate.timeIntervalSince(range.startDate)) > 1
      || abs(attributes.endDate.timeIntervalSince(range.endDate)) > 1
  }

  private func startLiveActivityForShift(_ shift: StoredShift) {
    let now = Date()
    guard let range = shiftDateRange(for: shift) else {
      return
    }

    let startDate = range.startDate
    let endDate = range.endDate

    let elapsed = now.timeIntervalSince(startDate)
    let total = endDate.timeIntervalSince(startDate)
    let progress = min(100, max(0, (elapsed / total) * 100))
    let hoursWorked = elapsed / 3600
    let totalRate = shift.hourlyWage + shift.supplementRatePerHour
    let earnings = hoursWorked * totalRate
    let remainingMinutes = max(0, Int((total - elapsed) / 60))

    // Calculate net amount if tax rate is configured
    let totalNetEstimate = shiftTotalNetEstimate(shift)

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
      isTemporaryClock: false,
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
    } catch {}
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

    apnsRegistrationInFlight = true
    defer { apnsRegistrationInFlight = false }

    do {
      // Route session access through AuthSessionManager to avoid refresh races
      // with other startup/foreground tasks that also need auth.
      let session = try await AuthSessionManager.shared.getSession()

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
          PushNotificationManager.shared.serverRegistrationFailed(errorMessage, underlying: nil)
        }
      }
    } catch {
      print("[APNs] Failed to register token: \(error)")
      await MainActor.run {
        PushNotificationManager.shared.serverRegistrationFailed(
          error.localizedDescription,
          underlying: error
        )
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
  private func shouldSuppressForegroundPresentation(for userInfo: [AnyHashable: Any]) -> Bool {
    let type = userInfo["type"] as? String ?? ""
    guard type == "thread_message",
      let threadId = userInfo["thread_id"] as? String
    else {
      return false
    }

    return MainActor.assumeIsolated {
      FriendsChatPresentationState.shared.activeThreadId == threadId
    }
  }

  // Handle notification when app is in foreground
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    if shouldSuppressForegroundPresentation(for: userInfo) {
      completionHandler([])
      return
    }

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
    // Handle friend chat message notifications
    else if type == "thread_message",
      let threadId = userInfo["thread_id"] as? String
    {
      let messageId = userInfo["message_id"] as? String
      let senderUserId = userInfo["sender_user_id"] as? String

      Task { @MainActor in
        AppCoordinator.shared.pendingDeepLink = .friendChat(
          threadId: threadId,
          messageId: messageId,
          senderUserId: senderUserId
        )
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
