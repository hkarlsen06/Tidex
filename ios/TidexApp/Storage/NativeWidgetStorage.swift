// swiftlint:disable explicit_type_interface
// swiftlint:disable:previous blanket_disable_command
import Foundation
import UIKit
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "NativeWidgetStorage")

// MARK: - Native Widget Storage

private actor NativeWidgetStorageRefreshCoordinator {
  static let shared = NativeWidgetStorageRefreshCoordinator()

  private struct RefreshWaiter {
    let generation: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private var activeUserIds: [String: Int] = [:]
  private var needsAnotherPass: Set<String> = []
  private var waiters: [String: [RefreshWaiter]] = [:]
  private var generation = 0

  func schedule(userId: String) {
    startRefreshIfNeeded(for: userId, generation: generation)
  }

  func refreshNow(userId: String) async {
    let refreshGeneration = generation
    await withCheckedContinuation { continuation in
      waiters[userId, default: []].append(
        RefreshWaiter(generation: refreshGeneration, continuation: continuation)
      )
      startRefreshIfNeeded(for: userId, generation: refreshGeneration)
    }
  }

  func invalidateAll() {
    generation += 1
    activeUserIds.removeAll()
    needsAnotherPass.removeAll()

    let staleWaiters = waiters.values.flatMap { waiters in
      waiters.map(\.continuation)
    }
    waiters.removeAll()
    staleWaiters.forEach { $0.resume() }
  }

  func shouldApplyResults(for userId: String, generation: Int) -> Bool {
    self.generation == generation && activeUserIds[userId] == generation
  }

  private func startRefreshIfNeeded(for userId: String, generation: Int) {
    if let activeGeneration = activeUserIds[userId] {
      guard activeGeneration == generation else { return }
      needsAnotherPass.insert(userId)
      return
    }

    activeUserIds[userId] = generation
    Task(priority: .utility) { [userId, generation] in
      await self.runRefreshLoop(for: userId, generation: generation)
    }
  }

  private func runRefreshLoop(for userId: String, generation: Int) async {
    while true {
      guard shouldApplyResults(for: userId, generation: generation) else { break }
      needsAnotherPass.remove(userId)
      await NativeWidgetStorage.performRefresh(for: userId, generation: generation)

      guard
        shouldApplyResults(for: userId, generation: generation),
        needsAnotherPass.contains(userId)
      else { break }
    }

    if activeUserIds[userId] == generation {
      activeUserIds.removeValue(forKey: userId)
    }

    let pendingWaiters = waiters[userId] ?? []
    let matchingWaiters = pendingWaiters.filter { $0.generation == generation }
    let remainingWaiters = pendingWaiters.filter { $0.generation != generation }

    if remainingWaiters.isEmpty {
      waiters.removeValue(forKey: userId)
    } else {
      waiters[userId] = remainingWaiters
    }

    matchingWaiters.forEach { $0.continuation.resume() }
  }
}

/// Writes shift data from SwiftData local storage to App Group UserDefaults
/// for widget consumption. This is the native-side equivalent of the WebView's
/// widget-storage.ts that writes via Capacitor.
///
/// Triggered after:
/// - Successful sync (SyncCoordinator)
/// - Local shift changes (ShiftsRepository)
enum NativeWidgetStorage {
  private static let appGroupId = "group.no.tidex.app"
  private static let shiftsKey = "upcoming_shifts"
  private static let currencyKey = "user_currency"
  private static let friendSharersKey = "friend_sharers"
  private static let friendShiftsKey = "friend_shifts"
  private static let monthlyTotalsKey = "monthly_totals"

  /// Default currency symbol if settings don't specify one
  private static let defaultCurrencySymbol = "kr"

  /// Storage window: previous month through 90 days ahead
  private static let futureDaysWindow = 90

  static func storedShift(
    _ shift: ShiftWithComputations, jobs: [Job], fallbackCurrency: String
  ) -> StoredShift {
    let job =
      shift.shift.job_id.flatMap { jobId in jobs.first { $0.id == jobId } }
      ?? jobs.first(where: \.is_default)
    let computed = shift.computed
    let hourlyWage =
      computed.paidHours > 0
      ? computed.basePay / computed.paidHours : computed.originalWagePeriods.first?.baseRate ?? 0
    return StoredShift(
      shiftId: shift.id,
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      hourlyWage: hourlyWage,
      supplementRatePerHour: calculateAverageSupplementRate(periods: computed.wagePeriods),
      totalGrossEstimate: computed.gross,
      currencySymbol: job?.currency ?? fallbackCurrency,
      taxRate: shift.taxEnabled ? shift.effectiveTaxPercentage / 100 : nil
    )
  }

  // MARK: - Public API

  /// Update widget storage with current local shift data
  /// - Parameter userId: User ID to fetch shifts for
  static func updateWidgetStorage(for userId: String) {
    Task(priority: .utility) {
      await NativeWidgetStorageRefreshCoordinator.shared.schedule(userId: userId)
    }
  }

  static func refreshWidgetStorageNow(for userId: String) async {
    await NativeWidgetStorageRefreshCoordinator.shared.refreshNow(userId: userId)
  }

  static func invalidatePendingRefreshes() async {
    await NativeWidgetStorageRefreshCoordinator.shared.invalidateAll()
  }

  static func performRefresh(for userId: String, generation: Int) async {
    logger.info("Updating widget storage for user \(userId.prefix(8))...")

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let settings = await storeActor.fetchUserSettings(userId: userId)
    let snapshots = await storeActor.fetchSnapshots(userId: userId)
    let recurringPatterns = await storeActor.fetchRecurringShifts(userId: userId)
    let jobs = await storeActor.fetchNonDeletedJobs(userId: userId)

    guard
      await NativeWidgetStorageRefreshCoordinator.shared.shouldApplyResults(
        for: userId,
        generation: generation
      )
    else { return }

    let currencySymbol = settings?.currency ?? defaultCurrencySymbol
    storeCurrency(currencySymbol)

    // Calculate date range: previous month through 90 days ahead
    let now = Date()
    let calendar = Calendar.current

    // First day of previous month - use Calendar.date(byAdding:) for safe month arithmetic
    // This correctly handles January -> December rollover without manual year/month math
    let firstDayOfCurrentMonth =
      calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
    let firstDayOfPreviousMonth =
      calendar.date(byAdding: .month, value: -1, to: firstDayOfCurrentMonth) ?? now
    let startDate = firstDayOfPreviousMonth

    // 90 days from now
    let endDate = calendar.date(byAdding: .day, value: futureDaysWindow, to: now) ?? now

    let computationWindow = PayrollReadWindow(startDate: startDate, endDate: endDate)
      .expandedForOvertime
    let regularShifts = await storeActor.fetchShifts(
      userId: userId,
      startDate: computationWindow.startDate,
      endDate: computationWindow.endDate
    )
    let yearMonth = now.yearMonth()
    let allShifts = PayrollEngine.computeShiftsForMonth(
      .init(
        year: yearMonth.year,
        month: yearMonth.month,
        shifts: regularShifts,
        recurring: recurringPatterns,
        snapshots: snapshots,
        settings: settings,
        visibleRange: (start: startDate, end: endDate),
        jobs: jobs
      ))

    if allShifts.isEmpty {
      guard
        await NativeWidgetStorageRefreshCoordinator.shared.shouldApplyResults(
          for: userId,
          generation: generation
        )
      else { return }

      logger.info("No shifts to store for widget")
      clearWidgetStorage()
      await MainActor.run {
        ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?
          .checkAndStartLiveActivityIfNeeded()
      }
      return
    }

    let storedShifts = allShifts.map { shift in
      storedShift(shift, jobs: jobs, fallbackCurrency: currencySymbol)
    }

    // Write to App Group UserDefaults
    guard
      await NativeWidgetStorageRefreshCoordinator.shared.shouldApplyResults(
        for: userId,
        generation: generation
      )
    else { return }
    writeShiftsToAppGroup(storedShifts)

    // Trigger widget reload
    reloadWidgetTimelines()

    // Re-check in-app Live Activity state after fresh shift data is written.
    await MainActor.run {
      ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?
        .checkAndStartLiveActivityIfNeeded()
    }

    // Schedule shift reminder notifications for upcoming shifts
    // Pass shifts directly to avoid race condition with UserDefaults write
    guard
      await NativeWidgetStorageRefreshCoordinator.shared.shouldApplyResults(
        for: userId,
        generation: generation
      )
    else { return }
    Task { @MainActor in
      await ShiftReminderScheduler.shared.scheduleAllReminders(for: userId, shifts: storedShifts)
      await EventReminderScheduler.shared.scheduleAllReminders(for: userId)
      await SmartNotificationScheduler.shared.scheduleSmartNotifications(for: userId)
    }

    logger.info("Widget storage updated with \(storedShifts.count) shifts")

    // Reuse the complete work weeks already loaded for both monthly totals.
    guard
      await NativeWidgetStorageRefreshCoordinator.shared.shouldApplyResults(
        for: userId,
        generation: generation
      )
    else { return }
    updateMonthlyTotalsStorage(
      settings: settings,
      snapshots: snapshots,
      recurringPatterns: recurringPatterns,
      currencySymbol: currencySymbol,
      jobs: jobs,
      currentMonthShifts: regularShifts,
      previousMonthShifts: regularShifts,
      now: now
    )
  }

  /// Clear widget storage (e.g., on logout)
  static func clearWidgetStorage() {
    guard let userDefaults = sharedUserDefaults() else {
      logger.warning("Unable to access App Group UserDefaults")
      return
    }

    userDefaults.removeObject(forKey: shiftsKey)
    userDefaults.removeObject(forKey: monthlyTotalsKey)
    reloadWidgetTimelines()

    // Cancel all scheduled shift reminders
    Task {
      await ShiftReminderScheduler.shared.cancelAllReminders()
      await EventReminderScheduler.shared.cancelAllReminders()
      await SmartNotificationScheduler.shared.cancelAllSmartNotifications()
    }

    logger.info("Widget storage cleared")
  }

  // MARK: - Monthly Totals Storage (TotalCard Widget)

  // Update widget storage with current month totals for the TotalCard widget.
  // Called automatically from updateWidgetStorage.
  // swiftlint:disable:next function_parameter_count
  private static func updateMonthlyTotalsStorage(
    settings: UserSettings?,
    snapshots: [WageSnapshot],
    recurringPatterns: [RecurringShiftRow],
    currencySymbol: String,
    jobs: [Job],
    currentMonthShifts: [ShiftRow],
    previousMonthShifts: [ShiftRow],
    now: Date
  ) {
    let calendar = Calendar.current

    // Get current month
    let currentYear = calendar.component(.year, from: now)
    let currentMonth = calendar.component(.month, from: now)

    // Calculate previous month date range
    let previousYM = Date.previousYearMonth(from: (year: currentYear, month: currentMonth))

    // Compute shifts with payroll using PayrollEngine
    let computedCurrentShifts = PayrollEngine.computeShiftsForMonth(
      .init(
        year: currentYear,
        month: currentMonth,
        shifts: currentMonthShifts,
        recurring: recurringPatterns,
        snapshots: snapshots,
        settings: settings,
        jobs: jobs
      )
    )

    let computedPreviousShifts = PayrollEngine.computeShiftsForMonth(
      .init(
        year: previousYM.year,
        month: previousYM.month,
        shifts: previousMonthShifts,
        recurring: recurringPatterns,
        snapshots: snapshots,
        settings: settings,
        jobs: jobs
      )
    )

    // Get half-tax month from settings
    let halfTaxMonth = settings?.half_tax_month

    // Calculate totals using PayrollEngine (handles half-tax and conflict exclusion)
    let currentTotals = PayrollEngine.summarizeShiftTotals(
      shifts: computedCurrentShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: currentMonth,
      now: now
    )

    let previousTotals = PayrollEngine.summarizeShiftTotals(
      shifts: computedPreviousShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: previousYM.month,
      now: now
    )

    // Determine if tax is enabled (from first shift or default to false)
    let taxEnabled = computedCurrentShifts.first?.taxEnabled ?? false

    // Count remaining (not-yet-completed) shifts.
    // Using end-time logic ensures same-day upcoming shifts are not counted as done.
    let plannedCount = computedCurrentShifts.filter { shift in
      !Date.hasShiftEnded(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        referenceDate: now
      )
    }.count

    // Calculate total hours worked this month
    let totalHours = computedCurrentShifts.map(\.paidHours).reduce(0.0, +)

    // Calculate percentage change vs previous month
    let percentageChange: Double? =
      previousTotals.gross > 0
      ? ((currentTotals.gross - previousTotals.gross) / previousTotals.gross) * 100
      : nil

    // Build StoredMonthlyTotals
    let monthlyTotals = StoredMonthlyTotals(
      gross: currentTotals.gross,
      net: taxEnabled ? currentTotals.net : nil,
      completedGross: currentTotals.completedGross,
      completedNet: taxEnabled ? currentTotals.completedNet : nil,
      shiftCount: computedCurrentShifts.count,
      plannedCount: plannedCount,
      totalHours: totalHours,
      percentageChange: percentageChange,
      yearMonth: String(format: "%04d-%02d", currentYear, currentMonth),
      taxEnabled: taxEnabled,
      currencySymbol: currencySymbol,
      updatedAt: now
    )

    // Write to App Group
    writeMonthlyTotalsToAppGroup(monthlyTotals)

    logger.info(
      "Monthly totals updated: gross=\(currentTotals.gross), shifts=\(computedCurrentShifts.count)")
  }

  /// Write monthly totals to App Group UserDefaults
  private static func writeMonthlyTotalsToAppGroup(_ totals: StoredMonthlyTotals) {
    guard let userDefaults = sharedUserDefaults() else {
      logger.warning("Unable to access App Group UserDefaults for monthly totals")
      return
    }

    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(totals)
      let jsonString = String(data: data, encoding: .utf8)
      userDefaults.set(jsonString, forKey: monthlyTotalsKey)
      logger.debug("Wrote monthly totals to App Group")
    } catch {
      logger.error("Failed to encode monthly totals for widget: \(error.localizedDescription)")
    }
  }

  // MARK: - Friend Widget Storage

  /// Update widget storage with friend/sharer data for the Friend's Shift widget
  /// - Parameters:
  ///   - sharers: List of users who share their shifts with the current user
  ///   - previews: Shift previews for each sharer
  @MainActor
  static func updateFriendWidgetStorage(
    sharers: [SharedUser],
    previews: [SharerShiftPreview]
  ) {
    logger.info(
      "Updating friend widget storage with \(sharers.count) sharers and \(previews.count) previews")

    guard let userDefaults = sharedUserDefaults() else {
      logger.warning("Unable to access App Group UserDefaults for friend widget storage")
      return
    }

    // Get currency
    let currencySymbol = userDefaults.string(forKey: currencyKey) ?? defaultCurrencySymbol

    // Convert sharers to WidgetSharer format
    let widgetSharers = sharers.map { $0.toWidgetSharer() }

    // Convert previews to StoredFriendShift format
    let storedShifts = previews.compactMap { preview in
      StoredFriendShift.from(
        preview: preview,
        currencySymbol: currencySymbol
      )
    }

    // Write to App Group UserDefaults
    writeFriendSharersToAppGroup(widgetSharers, userDefaults: userDefaults)
    writeFriendShiftsToAppGroup(storedShifts, userDefaults: userDefaults)

    // Reload widget timelines
    reloadWidgetTimelines()

    let avatarURLs = Dictionary(
      sharers.compactMap { sharer in sharer.avatarUrl.flatMap(URL.init(string:)).map { (sharer.id, $0) } },
      uniquingKeysWith: { first, _ in first }
    )
    Task.detached(priority: .utility) {
      await cacheFriendAvatars(avatarURLs)
    }

    logger.info(
      "Friend widget storage updated with \(widgetSharers.count) sharers and \(storedShifts.count) shifts"
    )
  }

  /// Clear friend widget storage (e.g., on logout)
  static func clearFriendWidgetStorage() {
    guard let userDefaults = sharedUserDefaults() else {
      logger.warning("Unable to access App Group UserDefaults")
      return
    }

    userDefaults.removeObject(forKey: friendSharersKey)
    userDefaults.removeObject(forKey: friendShiftsKey)
    if let directory = friendAvatarsDirectory() {
      try? FileManager.default.removeItem(at: directory)
    }
    reloadWidgetTimelines()

    logger.info("Friend widget storage cleared")
  }

  /// Widgets can't fetch remote images, so the app saves small avatar files
  /// named `<sharer id>.jpg` in the App Group for the Friends widget to read.
  private static func cacheFriendAvatars(_ urls: [String: URL]) async {
    guard let directory = friendAvatarsDirectory() else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    for file in existing where urls[(file as NSString).deletingPathExtension] == nil {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }

    var changed = false
    for (id, url) in urls {
      guard let (data, _) = try? await URLSession.shared.data(from: url),
        let image = UIImage(data: data),
        let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(width: 120, height: 120)),
        let jpeg = thumbnail.jpegData(compressionQuality: 0.85)
      else { continue }
      let fileURL = directory.appendingPathComponent("\(id).jpg")
      if (try? Data(contentsOf: fileURL)) != jpeg {
        try? jpeg.write(to: fileURL, options: .atomic)
        changed = true
      }
    }
    if changed {
      await MainActor.run { reloadWidgetTimelines() }
    }
  }

  private static func friendAvatarsDirectory() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
      .appendingPathComponent("friend-avatars", isDirectory: true)
  }

  private static func writeFriendSharersToAppGroup(
    _ sharers: [WidgetSharer], userDefaults: UserDefaults
  ) {
    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(sharers)
      let jsonString = String(data: data, encoding: .utf8)
      userDefaults.set(jsonString, forKey: friendSharersKey)
      logger.debug("Wrote \(sharers.count) friend sharers to App Group")
    } catch {
      logger.error("Failed to encode friend sharers for widget: \(error.localizedDescription)")
    }
  }

  private static func writeFriendShiftsToAppGroup(
    _ shifts: [StoredFriendShift], userDefaults: UserDefaults
  ) {
    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(shifts)
      let jsonString = String(data: data, encoding: .utf8)
      userDefaults.set(jsonString, forKey: friendShiftsKey)
      logger.debug("Wrote \(shifts.count) friend shifts to App Group")
    } catch {
      logger.error("Failed to encode friend shifts for widget: \(error.localizedDescription)")
    }
  }

  // MARK: - Private Helpers

  private static func sharedUserDefaults() -> UserDefaults? {
    guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil
    else {
      logger.error("App Group container not available: \(appGroupId)")
      return nil
    }
    return UserDefaults(suiteName: appGroupId)
  }

  private static func writeShiftsToAppGroup(_ shifts: [StoredShift]) {
    guard let userDefaults = sharedUserDefaults() else {
      logger.warning("Unable to access App Group UserDefaults")
      return
    }

    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(shifts)
      let jsonString = String(data: data, encoding: .utf8)
      userDefaults.set(jsonString, forKey: shiftsKey)
      logger.debug("Wrote \(shifts.count) shifts to App Group")
    } catch {
      logger.error("Failed to encode shifts for widget: \(error.localizedDescription)")
    }
  }

  private static func storeCurrency(_ currency: String) {
    guard let userDefaults = sharedUserDefaults() else {
      logger.warning("Unable to access App Group UserDefaults for currency")
      return
    }
    userDefaults.set(currency, forKey: currencyKey)
    logger.debug("Stored user currency: \(currency)")
  }

  private static func reloadWidgetTimelines() {
    WidgetCenter.shared.reloadAllTimelines()
    logger.debug("Widget timelines reloaded")
  }

  /// Calculate weighted average supplement rate from wage periods
  /// - Parameter periods: Array of wage periods
  /// - Returns: Weighted average supplement rate
  private static func calculateAverageSupplementRate(periods: [WagePeriod]) -> Double {
    guard !periods.isEmpty else { return 0 }

    var totalWeightedSupplement: Double = 0
    var totalMinutes: Double = 0

    for period in periods {
      totalWeightedSupplement += period.supplementRate * period.durationMinutes
      totalMinutes += period.durationMinutes
    }

    return totalMinutes > 0 ? totalWeightedSupplement / totalMinutes : 0
  }
}
