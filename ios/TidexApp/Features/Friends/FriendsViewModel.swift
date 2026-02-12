import Combine
import Foundation
import Supabase
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SharingViewModel")

// MARK: - Sharing Error

enum SharingError: Error, LocalizedError {
  case notAuthenticated
  case loadFailed(underlying: Error)
  case noSharers

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated"
    case .loadFailed(let error):
      return "Failed to load: \(error.localizedDescription)"
    case .noSharers:
      return "No one has shared shifts with you yet"
    }
  }
}

// MARK: - Sharing View Model

@MainActor
final class SharingViewModel: ObservableObject, MonthNavigable {

  // MARK: - Dependencies

  private let sharingService: SharingService
  private let sharedShiftsRepository: SharedShiftsRepository
  private let monthContext: SharedMonthContext

  // MARK: - Published State

  /// List of users who share their shifts with the current user
  @Published private(set) var sharers: [SharedUser] = []

  /// Currently selected sharer (nil shows sharer list)
  @Published var selectedSharer: SharedUser?

  /// Shifts from the selected sharer for the current month
  @Published private(set) var sharedShifts: [ShiftWithComputations] = []

  /// Whether sharers are being loaded
  @Published private(set) var isLoadingSharers = false

  /// Whether shifts are being loaded
  @Published private(set) var isLoadingShifts = false

  /// Current error state
  @Published private(set) var error: Error?

  /// Last cache time for currently displayed shifts
  @Published private(set) var lastCacheTime: Date?

  /// Direction of last navigation (for animations)
  @Published private(set) var navigationDirection: MonthNavigationDirection?

  /// Shift previews for each sharer (most relevant shift per sharer)
  @Published private(set) var shiftPreviews: [String: SharerShiftPreview] = [:]

  /// Whether shift previews are being loaded
  @Published private(set) var isLoadingPreviews = false

  /// Whether a pull-to-refresh is in progress (for shimmer on cards)
  @Published private(set) var isRefreshing = false

  // MARK: - Superimpose State

  /// Whether to show user's own shifts overlaid on friend's calendar
  @Published var isSuperimposing = false

  /// User's own shifts for the currently displayed month (raw data, no payroll needed)
  @Published private(set) var userShiftsForMonth: [ShiftRow] = []

  // MARK: - Committed Display State
  // These values only update AFTER shift data is ready, ensuring atomic rendering
  // The calendar uses these to avoid showing the new month structure before data arrives

  /// The year that is actually ready to display (data loaded)
  @Published private(set) var committedYear: Int

  /// The month that is actually ready to display (data loaded)
  @Published private(set) var committedMonth: Int

  // MARK: - Month Navigation (MonthNavigable)

  var displayYear: Int { monthContext.displayYear }
  var displayMonth: Int { monthContext.displayMonth }

  /// Whether viewing the current (real) month (based on committed state)
  var isCurrentMonth: Bool {
    let current = Date.currentYearMonth()
    return committedYear == current.year && committedMonth == current.month
  }

  /// Computed month name for immediate display (uses committed state for stability)
  var displayMonthName: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM"
    var components = DateComponents()
    components.year = committedYear
    components.month = committedMonth
    components.day = 1
    if let date = Calendar.current.date(from: components) {
      return formatter.string(from: date)
    }
    return ""
  }

  /// Required by MonthNavigable protocol
  var isLoading: Bool { isLoadingSharers || isLoadingShifts }

  // MARK: - Private State

  private var cachedUserId: String?
  private var monthContextCancellable: AnyCancellable?
  private var lastObservedYear: Int = 0
  private var lastObservedMonth: Int = 0
  private var selectedSharerLoadTask: Task<Void, Never>?
  private var inFlightRequestKey: String?

  // MARK: - Initialization

  init(
    sharingService: SharingService? = nil,
    sharedShiftsRepository: SharedShiftsRepository? = nil,
    monthContext: SharedMonthContext? = nil
  ) {
    self.sharingService = sharingService ?? SharingService.shared
    self.sharedShiftsRepository = sharedShiftsRepository ?? SharedShiftsRepository.shared
    self.monthContext = monthContext ?? SharedMonthContext.shared

    // Initialize committed state to current month context values
    // These will be updated atomically with shift data
    self.committedYear = self.monthContext.displayYear
    self.committedMonth = self.monthContext.displayMonth

    // Initialize tracking
    self.lastObservedYear = self.monthContext.displayYear
    self.lastObservedMonth = self.monthContext.displayMonth

    // Subscribe to month context changes
    setupMonthContextSubscription()
  }

  deinit {
    monthContextCancellable?.cancel()
    selectedSharerLoadTask?.cancel()
  }

  private func setupMonthContextSubscription() {
    monthContextCancellable = monthContext.monthChanged
      .receive(on: DispatchQueue.main)
      .sink { [weak self] newMonth in
        guard let self = self else { return }

        guard newMonth.year != self.lastObservedYear || newMonth.month != self.lastObservedMonth
        else {
          return
        }

        self.lastObservedYear = newMonth.year
        self.lastObservedMonth = newMonth.month
        self.navigationDirection = self.monthContext.navigationDirection

        // Reload shifts for new month if a sharer is selected
        if self.selectedSharer != nil {
          self.startSelectedSharerLoadTask()
        }
      }
  }

  private func startSelectedSharerLoadTask() {
    selectedSharerLoadTask?.cancel()
    selectedSharerLoadTask = Task { [weak self] in
      await self?.loadShiftsForSelectedSharer()
    }
  }

  // MARK: - Month Navigation

  func goToPreviousMonth() {
    monthContext.goToPreviousMonth()
  }

  func goToNextMonth() {
    monthContext.goToNextMonth()
  }

  func goToCurrentMonth() {
    monthContext.goToCurrentMonth()
  }

  /// Wait for sharers to be loaded (used for deep link handling)
  /// Returns when sharers are loaded or timeout is reached (3 seconds max)
  func waitForSharersLoaded() async {
    // If already loaded, return immediately
    guard sharers.isEmpty else { return }

    // Poll every 100ms until sharers are loaded (max 3 seconds)
    // We need to wait for loading to START and then COMPLETE
    let maxAttempts = 30
    for _ in 0..<maxAttempts {
      try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      if !sharers.isEmpty {
        return
      }
    }
  }

  // MARK: - Public Methods

  /// Load initial data (sharers list)
  /// - Parameter forceRefreshPreviews: If true, forces fresh preview data (used on pull-to-refresh)
  func loadSharers(forceRefreshPreviews: Bool = false) async {
    error = nil

    do {
      guard let userId = try await getCurrentUserId() else {
        throw SharingError.notAuthenticated
      }

      // Load from cache first (only if we have no data yet)
      // Load BOTH sharers and shift previews together to avoid pop-in effect
      // This happens BEFORE setting isLoadingSharers so view renders with complete data instantly
      var loadedFromCache = false
      if sharers.isEmpty {
        let cachedSharers = sharedShiftsRepository.getSharers(for: userId)
        if !cachedSharers.isEmpty {
          // Load cached shift previews at the same time
          let cachedPreviews = sharedShiftsRepository.getShiftPreviews(for: userId)

          // Update both together so UI renders with complete data and correct sorting
          sharers = cachedSharers
          if !cachedPreviews.isEmpty {
            shiftPreviews = cachedPreviews
          }
          loadedFromCache = true
          logger.info(
            "Loaded \(cachedSharers.count) sharers and \(cachedPreviews.count) previews from cache together"
          )
        }
      }

      // Only show loading indicator if we have no cached data
      if !loadedFromCache && sharers.isEmpty {
        isLoadingSharers = true
      }

      // Fetch fresh data from network
      logger.info("Fetching fresh sharers from network...")
      let freshSharers = try await sharingService.fetchSharers(for: userId)
      logger.info(
        "Network returned \(freshSharers.count) sharers: \(freshSharers.map { $0.displayName })")

      // Update UI with fresh data
      sharers = freshSharers
      logger.info("Updated sharers property, now has \(self.sharers.count) items")

      // Save to cache
      await sharedShiftsRepository.saveSharers(freshSharers, for: userId)

      logger.info("Loaded \(freshSharers.count) sharers")

      // Fetch shift previews after sharers loaded
      isLoadingSharers = false
      await loadShiftPreviews(forceRefresh: forceRefreshPreviews)

    } catch is CancellationError {
      // Task was cancelled (e.g., user released pull-to-refresh early)
      // This is not an error, just log and return
      logger.info("loadSharers was cancelled")
      isLoadingSharers = false
    } catch {
      // Check if the underlying error is a cancellation (URLError.cancelled)
      if let urlError = error as? URLError, urlError.code == .cancelled {
        logger.info("loadSharers network request was cancelled")
        isLoadingSharers = false
        return
      }

      logger.error("Failed to load sharers: \(error.localizedDescription)")
      self.error = SharingError.loadFailed(underlying: error)
      isLoadingSharers = false
    }
  }

  /// Load shift previews for all sharers
  /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data
  func loadShiftPreviews(forceRefresh: Bool = false) async {
    guard !sharers.isEmpty else { return }

    do {
      guard let userId = try await getCurrentUserId() else {
        throw SharingError.notAuthenticated
      }

      // Check if we already have cached data (loaded in loadSharers or from previous fetch)
      // This determines whether to animate the network data reveal
      var hasCachedData = !shiftPreviews.isEmpty

      // If we don't have data yet and not forcing refresh, try loading from cache
      if !forceRefresh && !hasCachedData {
        let cachedPreviews = sharedShiftsRepository.getShiftPreviews(for: userId)
        if !cachedPreviews.isEmpty {
          shiftPreviews = cachedPreviews
          hasCachedData = true
          logger.info("Loaded \(cachedPreviews.count) shift previews from persistent cache")
        }
      }

      // Only show loading animation if we have no data to display
      // This prevents animation when cached data is available
      if !hasCachedData && shiftPreviews.isEmpty {
        isLoadingPreviews = true
      }

      // Fetch fresh data from network
      let sharerIds = sharers.map { $0.id }
      let previews = try await sharingService.fetchShiftPreviews(
        sharerIds: sharerIds,
        forceRefresh: forceRefresh
      )

      // Convert to dictionary for quick lookup
      var previewMap: [String: SharerShiftPreview] = [:]
      for preview in previews {
        previewMap[preview.sharerId] = preview
      }

      // Animate the reveal only when loading fresh (no cached data)
      // When cached data exists, update silently (no animation needed)
      if !hasCachedData {
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
          shiftPreviews = previewMap
        }
      } else {
        shiftPreviews = previewMap
      }

      // Save to persistent cache
      await sharedShiftsRepository.saveShiftPreviews(previews, for: userId)

      // Update friend widget storage with sharers and previews
      if !sharers.isEmpty {
        NativeWidgetStorage.updateFriendWidgetStorage(
          sharers: sharers,
          previews: previews
        )
      }

      logger.info(
        "Loaded shift previews for \(previews.count) sharers (forceRefresh: \(forceRefresh))")
    } catch {
      logger.error("Failed to load shift previews: \(error.localizedDescription)")
      // Don't set error - previews are non-critical
    }

    isLoadingPreviews = false
  }

  /// Refresh sharers (pull-to-refresh) - forces fresh data
  /// Uses minimum refresh duration to ensure shimmer is visible
  ///
  /// IMPORTANT: SwiftUI's .refreshable cancels the task when the user releases the gesture.
  /// We use an unstructured Task to ensure the network work completes regardless of cancellation.
  func refresh() async {
    // Don't start another refresh if one is already in progress
    guard !isRefreshing else { return }

    // Set refreshing state immediately
    isRefreshing = true

    // Minimum 800ms ensures shimmer is visible even on fast connections
    let minimumDurationMs: UInt64 = 800
    let startTime = DispatchTime.now()

    // Capture state needed for the task
    let hasSelectedSharer = selectedSharer != nil

    // Create an unstructured task that will complete even if the parent is cancelled
    // This is necessary because SwiftUI's .refreshable cancels when the user releases
    let refreshTask = Task { @MainActor [weak self] in
      guard let self = self else { return }

      if hasSelectedSharer {
        await self.loadShiftsForSelectedSharer()
      } else {
        await self.loadSharers(forceRefreshPreviews: true)
      }
    }

    // Wait for the task to complete, ignoring any cancellation of our parent task
    _ = await refreshTask.result

    // Calculate elapsed time and wait for minimum duration
    // Use DispatchQueue.asyncAfter which is not cancelled by SwiftUI's .refreshable
    let elapsedMs = (DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
    let remainingMs = minimumDurationMs > elapsedMs ? minimumDurationMs - elapsedMs : 0

    if remainingMs > 0 {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(remainingMs))) {
          continuation.resume()
        }
      }
    }

    isRefreshing = false

    // Update Apple Watch with refreshed friend data
    if let userId = cachedUserId {
      WatchConnectivityManager.shared.sendUpdatedData(userId: userId)
    }
  }

  /// Select a sharer to view their shifts
  func selectSharer(_ sharer: SharedUser) {
    selectedSharer = sharer
    sharedShifts = []
    startSelectedSharerLoadTask()
  }

  /// Go back to sharer list
  func deselectSharer() {
    selectedSharerLoadTask?.cancel()
    selectedSharerLoadTask = nil
    inFlightRequestKey = nil
    selectedSharer = nil
    sharedShifts = []
    lastCacheTime = nil
  }

  /// Load shifts for the selected sharer and current month
  /// Commits display state (year/month) atomically with shift data
  func loadShiftsForSelectedSharer() async {
    guard let sharer = selectedSharer else { return }

    error = nil
    defer { isLoadingShifts = false }

    do {
      guard let userId = try await getCurrentUserId() else {
        throw SharingError.notAuthenticated
      }

      let year = displayYear
      let month = displayMonth
      let requestKey = "\(sharer.id):\(year):\(month)"

      if inFlightRequestKey == requestKey {
        logger.debug("Skipping duplicate shared shift request for \(year)-\(month)")
        return
      }
      inFlightRequestKey = requestKey
      defer {
        if inFlightRequestKey == requestKey {
          inFlightRequestKey = nil
        }
      }

      // Load from cache first (synchronously, before setting loading state)
      let cachedShifts = sharedShiftsRepository.getSharedShifts(
        ownerId: sharer.id,
        viewerId: userId,
        year: year,
        month: month
      )

      if !cachedShifts.isEmpty {
        // Cache hit - show cached data immediately, no loading flash
        // ATOMIC UPDATE: Set shifts and committed state together
        sharedShifts = cachedShifts
        committedYear = year
        committedMonth = month
        loadUserShifts(for: userId, year: year, month: month)
        lastCacheTime = sharedShiftsRepository.getLastCacheTime(
          ownerId: sharer.id,
          viewerId: userId,
          year: year,
          month: month
        )
        // Don't set isLoadingShifts - we have data to show
      } else if sharedShiftsRepository.hasFetchRecord(
        ownerId: sharer.id,
        viewerId: userId,
        year: year,
        month: month
      ) {
        // Previously fetched but empty - show empty calendar instantly, no loading
        sharedShifts = []
        committedYear = year
        committedMonth = month
        loadUserShifts(for: userId, year: year, month: month)
      } else {
        // Never fetched - DON'T clear shifts or update committed state
        // Keep showing previous month until new data is ready
        isLoadingShifts = true
      }

      // Fetch fresh data from API
      let response = try await sharingService.fetchSharedShifts(
        ownerId: sharer.id,
        year: year,
        month: month
      )

      // If selection/month changed while request was in-flight, ignore stale result.
      if selectedSharer?.id != sharer.id || displayYear != year || displayMonth != month {
        logger.info("Discarding stale shared shift result for \(year)-\(month)")
      } else {
        // Convert to ShiftWithComputations
        let freshShifts = response.shifts.map { $0.toShiftWithComputations() }

        // ATOMIC UPDATE: Set shifts and committed state together
        // This ensures the calendar structure and data update in the same render pass
        sharedShifts = freshShifts
        committedYear = year
        committedMonth = month
        lastCacheTime = Date()

        // Save to cache
        await sharedShiftsRepository.saveSharedShifts(
          response.shifts,
          ownerId: sharer.id,
          viewerId: userId,
          showEarnings: sharer.showEarnings,
          year: year,
          month: month
        )

        logger.info("Loaded \(freshShifts.count) shared shifts for \(year)-\(month)")
      }

    } catch is CancellationError {
      logger.info("Shared shifts load cancelled")
    } catch {
      if let urlError = error as? URLError, urlError.code == .cancelled {
        logger.info("Shared shifts network request cancelled")
      } else {
        logger.error("Failed to load shared shifts: \(error.localizedDescription)")
        self.error = SharingError.loadFailed(underlying: error)
      }
    }

    if let userId = cachedUserId {
      loadUserShifts(for: userId, year: committedYear, month: committedMonth)
    } else {
      await loadUserShiftsForMonth()
    }
  }

  /// Load user's own shifts for the current month (for overlap indicators + superimpose feature)
  /// Includes both real shifts and virtual shifts from recurring patterns
  func loadUserShiftsForMonth() async {
    // Get user ID from cache or fetch
    var userId = cachedUserId
    if userId == nil {
      userId = try? await getCurrentUserId()
    }

    guard let userId else {
      userShiftsForMonth = []
      return
    }

    loadUserShifts(for: userId, year: committedYear, month: committedMonth)
  }

  /// Load user's own shifts for a specific month from local repositories.
  private func loadUserShifts(for userId: String, year: Int, month: Int) {

    // Calculate date range for the month
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1

    guard let startDate = Calendar.current.date(from: components),
      let endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate)?
        .addingTimeInterval(-1)
    else {
      userShiftsForMonth = []
      return
    }

    // Fetch user's real shifts from local repository
    var allShifts = ShiftsRepository.shared.getShifts(
      for: userId,
      startDate: startDate,
      endDate: endDate
    )

    // Get recurring shifts and generate virtual shifts
    let recurringShifts = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)
    // Track real shifts by date+time to detect duplicates from materialized recurring shifts
    let realShiftKeys = Set(allShifts.map { "\($0.shift_date)|\($0.start_time)|\($0.end_time)" })

    for recurring in recurringShifts {
      let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
        year: year,
        month: month,
        recurring: recurring
      )

      for virtual in virtualShifts {
        // Skip if a real shift with matching times exists (materialized recurring shift)
        let key = "\(virtual.date)|\(recurring.cleanStartTime)|\(recurring.cleanEndTime)"
        if realShiftKeys.contains(key) { continue }

        // Create virtual shift row with times from recurring pattern
        let virtualRow = ShiftRow(
          id: "virtual-\(recurring.id)-\(virtual.date)",
          user_id: recurring.user_id,
          shift_date: virtual.date,
          start_time: recurring.cleanStartTime,
          end_time: recurring.cleanEndTime,
          custom_supplements: recurring.date_specific_supplements?[virtual.date],
          created_at: nil,
          recurring_id: recurring.id,
          recurring_anchor_weekday: virtual.weekday
        )
        allShifts.append(virtualRow)
      }
    }

    userShiftsForMonth = allShifts
    logger.info(
      "Loaded \(allShifts.count) user shifts for superimpose (\(year)-\(month)) - includes virtual shifts"
    )
  }

  /// Toggle superimpose mode and load user shifts if needed
  func toggleSuperimpose() {
    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
      isSuperimposing.toggle()
    }
    Task {
      await loadUserShiftsForMonth()
    }
  }

  // MARK: - Computed Properties

  /// Whether the view should show the sharer list (no sharer selected)
  var showingSharerList: Bool {
    selectedSharer == nil
  }

  /// Whether there are no sharers at all
  var hasNoSharers: Bool {
    sharers.isEmpty && !isLoadingSharers
  }

  /// Whether earnings are visible for the selected sharer
  var showEarnings: Bool {
    selectedSharer?.showEarnings ?? false
  }

  /// Total hours for the current month's shifts
  var totalHours: Double {
    sharedShifts.reduce(0) { $0 + $1.paidHours }
  }

  /// Total earnings for the current month's shifts (nil if earnings hidden)
  /// Returns the net earnings (after tax)
  var totalEarnings: Double? {
    guard showEarnings else { return nil }
    return sharedShifts.reduce(0) { $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay) }
  }

  /// Gross earnings for the current month's shifts (nil if earnings hidden)
  var totalGrossEarnings: Double? {
    guard showEarnings else { return nil }
    return sharedShifts.reduce(0) { $0 + $1.grossPay }
  }

  /// Whether any shift in the current month has tax enabled
  var hasTaxEnabled: Bool {
    sharedShifts.contains { $0.taxEnabled }
  }

  /// Shift count for the current month
  var shiftCount: Int {
    sharedShifts.count
  }

  // MARK: - Superimpose Computed Properties

  /// Hours data by ISO date string for user's shifts
  var userHoursByDate: [String: HoursData] {
    var shiftsByDateDict: [String: [ShiftRow]] = [:]
    for shift in userShiftsForMonth {
      shiftsByDateDict[shift.shift_date, default: []].append(shift)
    }

    var result: [String: HoursData] = [:]
    for (date, shiftsOnDate) in shiftsByDateDict {
      let sorted = shiftsOnDate.sorted { $0.start_time < $1.start_time }
      let earliestStart = sorted.first?.start_time ?? ""
      let latestEnd = sorted.map(\.end_time).max() ?? ""

      let crossesMidnight = shiftsOnDate.contains { shift in
        let startMinutes = CalendarGridHelper.timeToMinutes(shift.start_time)
        let endMinutes = CalendarGridHelper.timeToMinutes(shift.end_time)
        return endMinutes <= startMinutes
      }

      result[date] = HoursData(
        start: CalendarGridHelper.formatTime(earliestStart),
        end: CalendarGridHelper.formatTime(latestEnd),
        crossesMidnight: crossesMidnight
      )
    }
    return result
  }

  // MARK: - Private Methods

  private func getCurrentUserId() async throws -> String? {
    if let cached = cachedUserId {
      return cached
    }

    // Use AuthSessionManager to prevent concurrent refresh race conditions
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId
    cachedUserId = userId
    return userId
  }
}
