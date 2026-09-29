import Combine
import Foundation
import Observation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SharingViewModel")

enum FriendInitialMonthResolver {
  static func targetYearMonth(
    sharer: SharedUser,
    preview: SharerShiftPreview?,
    current: (year: Int, month: Int)
  ) -> (year: Int, month: Int)? {
    if let previewShift = preview?.shift,
      let previewDate = Date.fromISODateString(previewShift.shift_date)
    {
      let components = Calendar.gregorianCurrent.dateComponents([.year, .month], from: previewDate)
      if let year = components.year, let month = components.month,
        year != current.year || month != current.month
      {
        return (year, month)
      }
      return nil
    }

    guard !sharer.hasRecurringSharedShifts,
      let latestSharedShiftDate = sharer.latestSharedShiftDate,
      let latestShiftDate = Date.fromISODateString(latestSharedShiftDate)
    else {
      return nil
    }

    let components = Calendar.gregorianCurrent.dateComponents(
      [.year, .month], from: latestShiftDate)
    guard let year = components.year, let month = components.month else { return nil }
    guard year != current.year || month != current.month else { return nil }
    return (year, month)
  }
}

// MARK: - Sharing Error

enum SharingError: Error, LocalizedError {
  case notAuthenticated
  case loadFailed(underlying: Error)
  case noSharers

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return String(localized: .commonErrorNotAuthenticated)

    case .loadFailed:
      return String(localized: .commonErrorLoadFailed)

    case .noSharers:
      return String(localized: .friendsErrorNoSharers)
    }
  }
}

// MARK: - Sharing View Model

@MainActor
@Observable
final class SharingViewModel: MonthNavigable {

  // MARK: - Dependencies

  private let sharingService: SharingService
  private let sharedShiftsRepository: SharedShiftsRepository
  private let monthContext: SharedMonthContext
  private let visibilityStore: FriendsVisibilityStore

  // MARK: - Published State

  /// List of users who share their shifts with the current user
  private(set) var sharers: [SharedUser] = []

  /// Users who share their shifts with the current user but are hidden from the main list
  private(set) var hiddenSharers: [SharedUser] = []

  /// Users the viewer shares with, but who do not share back.
  private(set) var chatOnlyUserIds: Set<String> = []

  /// Currently selected sharer (nil shows sharer list)
  var selectedSharer: SharedUser?

  /// Shifts from the selected sharer for the currently visible calendar range
  /// (includes out-of-month padding days for the committed month grid)
  private(set) var sharedShifts: [ShiftWithComputations] = []

  /// Job metadata for currently selected sharer
  private(set) var sharedJobs: [SharedJob] = []

  /// Currency for currently selected sharer (from shared settings payload)
  private(set) var sharedCurrency: String?

  /// Whether sharers are being loaded
  private(set) var isLoadingSharers = false

  /// Whether the initial sharers state has been resolved (cache or first fetch attempt).
  /// Prevents an empty-state flash on first frame before cache/network hydration starts.
  private(set) var hasFinishedInitialSharersLoad = false

  /// Whether shifts are being loaded
  private(set) var isLoadingShifts = false

  /// Whether the selected sharer's shift content has resolved from cache or network.
  private(set) var hasResolvedSelectedSharerShifts = true

  /// Current error state
  private(set) var error: Error?

  /// Last cache time for currently displayed shifts
  private(set) var lastCacheTime: Date?

  /// Direction of last navigation (for animations)
  var navigationDirection: MonthNavigationDirection? { monthContext.navigationDirection }

  /// Shift previews for each sharer (most relevant shift per sharer)
  private(set) var shiftPreviews: [String: SharerShiftPreview] = [:]

  /// Latest management-sheet payload from the Friends tab bootstrap RPC.
  private(set) var managementSnapshot = FriendsManagementSnapshot(
    friends: [],
    blockedFriends: []
  )

  /// Whether shift previews are being loaded
  private(set) var isLoadingPreviews = false

  /// Whether a pull-to-refresh is in progress (for shimmer on cards)
  private(set) var isRefreshing = false

  // MARK: - Superimpose State

  /// Whether to show user's own shifts overlaid on friend's calendar
  var isSuperimposing = false

  /// User's own shifts for the currently visible calendar range (raw data, no payroll needed)
  private(set) var userShiftsForMonth: [ShiftRow] = []

  /// User's own earnings by date for the currently visible calendar range
  private(set) var userEarningsByDate: [String: CalendarEarningsData] = [:]

  // MARK: - Committed Display State
  // These values only update AFTER shift data is ready, ensuring atomic rendering
  // The calendar uses these to avoid showing the new month structure before data arrives

  /// The year that is actually ready to display (data loaded)
  private(set) var committedYear: Int

  /// The month that is actually ready to display (data loaded)
  private(set) var committedMonth: Int

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
    if let date = Calendar.gregorianCurrent.date(from: components) {
      return formatter.string(from: date)
    }
    return ""
  }

  /// Required by MonthNavigable protocol
  var isLoading: Bool { isLoadingSharers || isLoadingShifts }

  /// Current transition phase for month animations
  var transitionPhase: MonthTransitionPhase {
    MonthTransitionPhase(
      year: committedYear,
      month: committedMonth,
      direction: navigationDirection
    )
  }

  // MARK: - Private State

  @ObservationIgnored private var cachedUserId: String?
  @ObservationIgnored private var locallyBlockedUserIds: Set<String> = []
  @ObservationIgnored private var monthContextCancellable: AnyCancellable?
  @ObservationIgnored private var lastObservedYear: Int = 0
  @ObservationIgnored private var lastObservedMonth: Int = 0
  @ObservationIgnored private var selectedSharerLoadTask: Task<Void, Never>?
  @ObservationIgnored private var inFlightRequestKey: String?
  @ObservationIgnored private var userShiftsComputationGeneration: UInt64 = 0

  private struct UserShiftComputationInput {
    let userId: String
    let year: Int
    let month: Int
    let visibleRange: (start: Date, end: Date)
    let monthsInVisibleRange: [(year: Int, month: Int)]
    let shifts: [ShiftRow]
    let recurringShifts: [RecurringShiftRow]
    let settings: UserSettings
    let snapshots: [WageSnapshot]
    let jobs: [Job]
  }

  private struct UserShiftComputationResult {
    let shifts: [ShiftRow]
    let earningsByDate: [String: CalendarEarningsData]
  }

  private struct YearMonthKey: Hashable {
    let year: Int
    let month: Int
  }

  // MARK: - Initialization

  init(
    sharingService: SharingService? = nil,
    sharedShiftsRepository: SharedShiftsRepository? = nil,
    monthContext: SharedMonthContext? = nil,
    visibilityStore: FriendsVisibilityStore? = nil
  ) {
    self.sharingService = sharingService ?? SharingService.shared
    self.sharedShiftsRepository = sharedShiftsRepository ?? SharedShiftsRepository.shared
    self.monthContext = monthContext ?? SharedMonthContext.shared
    self.visibilityStore = visibilityStore ?? FriendsVisibilityStore.shared

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
        // swiftlint:disable:next conditional_returns_on_newline
        guard let self else { return }

        guard newMonth.year != lastObservedYear || newMonth.month != lastObservedMonth
        else {
          return
        }

        lastObservedYear = newMonth.year
        lastObservedMonth = newMonth.month

        // Reload shifts for new month if a sharer is selected
        if selectedSharer != nil {
          startSelectedSharerLoadTask()
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
    // swiftlint:disable:next conditional_returns_on_newline
    guard sharers.isEmpty, hiddenSharers.isEmpty else { return }

    // Poll every 100ms until sharers are loaded (max 3 seconds)
    // We need to wait for loading to START and then COMPLETE
    let maxAttempts = 30
    for _ in 0..<maxAttempts {
      try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      if !sharers.isEmpty || !hiddenSharers.isEmpty {
        return
      }
    }
  }

  // MARK: - Public Methods

  /// Load initial Friends tab data through the consolidated bootstrap RPC.
  func loadSharers(forceRefreshPreviews: Bool = false) async {
    _ = forceRefreshPreviews
    error = nil

    do {
      guard let userId = try await getCurrentUserId() else {
        throw SharingError.notAuthenticated
      }

      // Load from cache first (only if we have no data yet)
      // Load BOTH sharers and shift previews together to avoid pop-in effect
      // This happens BEFORE setting isLoadingSharers so view renders with complete data instantly
      var loadedFromCache = false
      if sharers.isEmpty, hiddenSharers.isEmpty {
        let cachedFriends = sharedShiftsRepository.getCachedFriends(
          for: userId, includeHidden: true)
        if !cachedFriends.sharers.isEmpty {
          // Load cached shift previews at the same time
          let cachedPreviews = sharedShiftsRepository.getShiftPreviews(for: userId)
          let filteredCachedSharers = filteredBlockedUsers(from: cachedFriends.sharers)
          let partitionedSharers = partitionSharers(filteredCachedSharers)

          if !cachedPreviews.isEmpty {
            // Update both together so UI renders with complete data and correct sorting
            shiftPreviews = cachedPreviews.filter { !locallyBlockedUserIds.contains($0.key) }
            sharers = partitionedSharers.visible
            hiddenSharers = partitionedSharers.hidden
            chatOnlyUserIds = cachedFriends.chatOnlyUserIds.subtracting(locallyBlockedUserIds)
            loadedFromCache = true
            hasFinishedInitialSharersLoad = true
            logger.info(
              """
              Loaded \(self.sharers.count) visible sharers, \(self.hiddenSharers.count) hidden sharers,
              and \(cachedPreviews.count) previews from cache together
              """
            )
          } else {
            logger.info("Skipping cached sharers because no cached preview sort order is available")
          }
        }
      }

      // Only show loading indicator if we have no cached data
      if !loadedFromCache, sharers.isEmpty, hiddenSharers.isEmpty {
        isLoadingSharers = true
        isLoadingPreviews = true
      }

      logger.info("Fetching Friends tab bootstrap from network...")
      let bootstrap = try await sharingService.fetchFriendsTabBootstrap()
      await applyFriendsTabBootstrap(
        bootstrap,
        userId: userId,
        animatePreviewReveal: !loadedFromCache && shiftPreviews.isEmpty
      )

      logger.info(
        "Loaded \(self.sharers.count) visible sharers and \(self.hiddenSharers.count) hidden sharers"
      )

      isLoadingSharers = false
      isLoadingPreviews = false
      await persistShiftPreviews(bootstrap.previews, userId: userId)

    } catch is CancellationError {
      // Task was cancelled (e.g., user released pull-to-refresh early)
      // This is not an error, just log and return
      logger.info("loadSharers was cancelled")
      isLoadingSharers = false
      isLoadingPreviews = false
    } catch {
      // Check if the underlying error is a cancellation (URLError.cancelled)
      if let urlError = error as? URLError, urlError.code == .cancelled {
        logger.info("loadSharers network request was cancelled")
        isLoadingSharers = false
        isLoadingPreviews = false
        return
      }

      logger.error("Failed to load sharers: \(error.localizedDescription)")
      self.error = SharingError.loadFailed(underlying: error)
      if sharers.isEmpty, hiddenSharers.isEmpty {
        hasFinishedInitialSharersLoad = true
        chatOnlyUserIds = []
      }
      isLoadingSharers = false
      isLoadingPreviews = false
    }
  }

  private func previewMap(from previews: [SharerShiftPreview]) -> [String: SharerShiftPreview] {
    var map: [String: SharerShiftPreview] = [:]
    for preview in previews {
      map[preview.sharerId] = preview
    }
    return map
  }

  func applyFriendsTabBootstrap(_ bootstrap: FriendsTabBootstrapData) async {
    guard let userId = try? await getCurrentUserId() else { return }
    await applyFriendsTabBootstrap(
      bootstrap,
      userId: userId,
      animatePreviewReveal: false
    )
    await persistShiftPreviews(bootstrap.previews, userId: userId)
  }

  private func applyFriendsTabBootstrap(
    _ bootstrap: FriendsTabBootstrapData,
    userId: String,
    animatePreviewReveal: Bool
  ) async {
    managementSnapshot = bootstrap.managementSnapshot

    let blockedUserIds = Set(bootstrap.blockedFriends.map(\.id))
    locallyBlockedUserIds = blockedUserIds

    let filteredFreshSharers = bootstrap.sharers.filter { !blockedUserIds.contains($0.id) }
    let outgoingChatSharers = chatOnlySharers(
      from: bootstrap.friends,
      excluding: Set(filteredFreshSharers.map(\.id)).union(blockedUserIds),
      viewerId: userId
    )
    logger.info(
      "Network returned \(filteredFreshSharers.count) non-blocked sharers: \(filteredFreshSharers.map(\.displayName))"
    )

    let partitionedSharers = partitionSharers(filteredFreshSharers)
    let partitionedOutgoingChatSharers = partitionSharers(outgoingChatSharers)
    let freshPreviewMap = previewMap(from: bootstrap.previews)
      .filter { !blockedUserIds.contains($0.key) }

    if animatePreviewReveal {
      withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(duration: 0.4, bounce: 0.15)) {
        shiftPreviews = freshPreviewMap
      }
    } else {
      shiftPreviews = freshPreviewMap
    }

    sharers = partitionedSharers.visible + partitionedOutgoingChatSharers.visible
    hiddenSharers = partitionedSharers.hidden + partitionedOutgoingChatSharers.hidden
    chatOnlyUserIds = Set(outgoingChatSharers.map(\.id))
    if let selectedSharer,
      !(sharers + hiddenSharers).contains(where: { $0.id == selectedSharer.id })
    {
      deselectSharer()
    }
    hasFinishedInitialSharersLoad = true
    logger.info(
      """
      Updated sharers properties, now has \(self.sharers.count) visible and
      \(self.hiddenSharers.count) hidden items (\(outgoingChatSharers.count) chat-only)
      """
    )

    await sharedShiftsRepository.saveSharers(
      sharers + hiddenSharers,
      chatOnlyUserIds: chatOnlyUserIds,
      for: userId
    )
  }

  private func persistShiftPreviews(_ previews: [SharerShiftPreview], userId: String) async {
    guard !previews.isEmpty else { return }

    await sharedShiftsRepository.saveShiftPreviews(previews, for: userId)

    let widgetSharers = sharers.filter { !chatOnlyUserIds.contains($0.id) }
    if !widgetSharers.isEmpty {
      NativeWidgetStorage.updateFriendWidgetStorage(
        sharers: widgetSharers,
        previews: previews
      )
    }
  }

  func handleBlockedUser(_ userId: String) {
    locallyBlockedUserIds.insert(userId)
    sharers.removeAll { $0.id == userId }
    hiddenSharers.removeAll { $0.id == userId }
    chatOnlyUserIds.remove(userId)
    shiftPreviews.removeValue(forKey: userId)

    if selectedSharer?.id == userId {
      deselectSharer()
    }
  }

  func handleUnblockedUser(_ userId: String) {
    locallyBlockedUserIds.remove(userId)
  }

  private func filteredBlockedUsers(from users: [SharedUser]) -> [SharedUser] {
    users.filter { !locallyBlockedUserIds.contains($0.id) }
  }

  private func partitionSharers(_ sharers: [SharedUser]) -> (
    visible: [SharedUser], hidden: [SharedUser]
  ) {
    var visible: [SharedUser] = []
    var hidden: [SharedUser] = []

    for sharer in sharers {
      if sharer.hidden {
        hidden.append(sharer)
      } else {
        visible.append(sharer)
      }
    }

    return (visible, hidden)
  }

  private func chatOnlySharers(
    from friends: [Friend],
    excluding sharerIds: Set<String>,
    viewerId: String
  )
    -> [SharedUser]
  {
    let hiddenOutgoingFriendIds = visibilityStore.hiddenOutgoingFriendIds(for: viewerId)

    return friends.compactMap { friend in
      guard friend.isOutgoingOnly, !sharerIds.contains(friend.id), let share = friend.iShareWith
      else {
        return nil
      }

      return SharedUser(
        id: friend.id,
        email: friend.email,
        phone: friend.phone,
        firstName: friend.firstName,
        profilePictureUrl: friend.profilePictureUrl,
        oauthAvatarUrl: friend.oauthAvatarUrl,
        sharedAt: share.sharedAt,
        showEarnings: false,
        hidden: hiddenOutgoingFriendIds.contains(friend.id)
      )
    }
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
      // swiftlint:disable:next conditional_returns_on_newline
      guard let self else { return }

      if hasSelectedSharer {
        await loadShiftsForSelectedSharer()
      } else {
        await loadSharers(forceRefreshPreviews: true)
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
  }

  /// Select a sharer to view their shifts
  func selectSharer(_ sharer: SharedUser) {
    selectedSharer = sharer
    hasResolvedSelectedSharerShifts = false
    sharedShifts = []
    sharedJobs = []
    sharedCurrency = nil
    Task {
      await NotificationService.shared.clearDeliveredSharedShiftNotifications(for: sharer.id)
    }

    let currentMonth = (year: displayYear, month: displayMonth)
    if let targetMonth = FriendInitialMonthResolver.targetYearMonth(
      sharer: sharer,
      preview: shiftPreviews[sharer.id],
      current: currentMonth
    ) {
      monthContext.navigateTo(year: targetMonth.year, month: targetMonth.month)
      return
    }

    startSelectedSharerLoadTask()
  }

  /// Go back to sharer list
  func deselectSharer() {
    selectedSharerLoadTask?.cancel()
    selectedSharerLoadTask = nil
    inFlightRequestKey = nil
    selectedSharer = nil
    hasResolvedSelectedSharerShifts = true
    sharedShifts = []
    sharedJobs = []
    sharedCurrency = nil
    userShiftsForMonth = []
    userEarningsByDate = [:]
    lastCacheTime = nil
  }

  private struct SharedShiftsLoadRequest {
    let sharer: SharedUser
    let userId: String
    let year: Int
    let month: Int
    let monthWindow: [YearMonthKey]
    let visibleRange: (start: Date, end: Date)

    var key: String { "\(sharer.id):\(year):\(month)" }

    @MainActor init(sharer: SharedUser, userId: String, year: Int, month: Int) {
      self.sharer = sharer
      self.userId = userId
      self.year = year
      self.month = month
      monthWindow = SharingViewModel.monthWindowForVisibleRange(year: year, month: month)
      visibleRange = Date.visibleCalendarRange(year: year, month: month)
    }
  }

  private func isStale(_ request: SharedShiftsLoadRequest) -> Bool {
    selectedSharer?.id != request.sharer.id || displayYear != request.year
      || displayMonth != request.month
  }

  private func handleSharedShiftsLoadError(_ error: Error) {
    if error is CancellationError {
      logger.info("Shared shifts load cancelled")
    } else if let urlError = error as? URLError, urlError.code == .cancelled {
      logger.info("Shared shifts network request cancelled")
    } else {
      logger.error("Failed to load shared shifts: \(error.localizedDescription)")
      self.error = SharingError.loadFailed(underlying: error)
      hasResolvedSelectedSharerShifts = true
    }
  }

  /// Shows cached shifts for the request before the network fetch starts (synchronously, before
  /// setting loading state). Merges previous/current/next month cache so out-of-month calendar
  /// days are populated.
  private func applyCachedSharedShifts(_ request: SharedShiftsLoadRequest) {
    let sharer = request.sharer
    let userId = request.userId
    let year = request.year
    let month = request.month

    let cachedShiftSets = request.monthWindow.map { key in
      sharedShiftsRepository.getSharedShifts(
        ownerId: sharer.id,
        viewerId: userId,
        year: key.year,
        month: key.month
      )
    }
    let cachedShifts = Self.mergeSharedShifts(
      cachedShiftSets,
      visibleRange: request.visibleRange
    )

    if !cachedShifts.isEmpty {
      // Cache hit - show cached data immediately, no loading flash
      // ATOMIC UPDATE: Set shifts and committed state together
      sharedShifts = cachedShifts
      hasResolvedSelectedSharerShifts = true
      committedYear = year
      committedMonth = month
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
      hasResolvedSelectedSharerShifts = true
      committedYear = year
      committedMonth = month
    } else {
      // Never fetched - DON'T clear shifts or update committed state
      // Keep showing previous month until new data is ready
      isLoadingShifts = true
    }
  }

  private func applyFreshSharedShifts(
    _ request: SharedShiftsLoadRequest,
    responsesByMonth: [YearMonthKey: SharedShiftsResponse]
  ) async {
    let year = request.year
    let month = request.month

    var freshShiftSets: [[ShiftWithComputations]] = []
    for key in request.monthWindow {
      guard let response = responsesByMonth[key] else { continue }
      let converted = await Self.convertSharedShiftsOffMain(response.shifts)
      freshShiftSets.append(converted)
    }
    let freshShifts = Self.mergeSharedShifts(
      freshShiftSets,
      visibleRange: request.visibleRange
    )
    let currentMonthResponse = responsesByMonth[YearMonthKey(year: year, month: month)]

    // ATOMIC UPDATE: Set shifts and committed state together
    // This ensures the calendar structure and data update in the same render pass
    sharedShifts = freshShifts
    sharedJobs = currentMonthResponse?.jobs ?? []
    sharedCurrency = currentMonthResponse?.settings.currency
    hasResolvedSelectedSharerShifts = true
    committedYear = year
    committedMonth = month
    lastCacheTime = Date()

    // Save each month payload to cache.
    for key in request.monthWindow {
      guard let response = responsesByMonth[key] else { continue }
      await sharedShiftsRepository.saveSharedShifts(
        response.shifts,
        ownerId: request.sharer.id,
        viewerId: request.userId,
        showEarnings: request.sharer.showEarnings,
        year: key.year,
        month: key.month
      )
    }

    logger.info("Loaded \(freshShifts.count) shared shifts for \(year)-\(month)")
  }

  /// Load shifts for the selected sharer and current month
  /// Commits display state (year/month) atomically with shift data
  func loadShiftsForSelectedSharer() async {
    guard let sharer = selectedSharer else { return }

    error = nil

    do {
      guard let userId = try await getCurrentUserId() else {
        throw SharingError.notAuthenticated
      }

      let request = SharedShiftsLoadRequest(
        sharer: sharer, userId: userId, year: displayYear, month: displayMonth)
      let requestKey = request.key

      if inFlightRequestKey == requestKey {
        logger.debug(
          "Skipping duplicate shared shift request for \(request.year)-\(request.month)")
        return
      }
      inFlightRequestKey = requestKey
      defer {
        isLoadingShifts = false
        if inFlightRequestKey == requestKey {
          inFlightRequestKey = nil
        }
      }

      applyCachedSharedShifts(request)

      // Fetch fresh data from API for the visible month window.
      let responsesByMonth = try await fetchSharedShiftsForMonthWindow(
        ownerId: sharer.id,
        monthWindow: request.monthWindow
      )

      // If selection/month changed while request was in-flight, ignore stale result.
      if isStale(request) {
        logger.info("Discarding stale shared shift result for \(request.year)-\(request.month)")
      } else {
        await applyFreshSharedShifts(request, responsesByMonth: responsesByMonth)
      }
    } catch {
      handleSharedShiftsLoadError(error)
    }

    if let userId = cachedUserId {
      await loadUserShifts(for: userId, year: committedYear, month: committedMonth)
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
      userEarningsByDate = [:]
      return
    }

    await loadUserShifts(for: userId, year: committedYear, month: committedMonth)
  }

  /// Load user's own shifts for a specific month from local repositories.
  private func loadUserShifts(for userId: String, year: Int, month: Int) async {
    let visibleRange = Date.visibleCalendarRange(year: year, month: month)
    let monthsInVisibleRange = Self.monthsInRange(
      startDate: visibleRange.start,
      endDate: visibleRange.end
    )

    // Fetch user's real shifts from local repositories
    let shifts = ShiftsRepository.shared.getShifts(
      for: userId,
      startDate: visibleRange.start,
      endDate: visibleRange.end
    )
    let recurringShifts = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)

    guard
      let settings = SettingsRepository.shared.getSettings(for: userId)
    else {
      userShiftsForMonth = shifts
      userEarningsByDate = [:]
      return
    }

    let snapshots = SnapshotsRepository.shared.getSnapshots(for: userId)
    let jobs = JobsRepository.shared.getNonDeletedJobs(for: userId)

    userShiftsComputationGeneration &+= 1
    let generation = userShiftsComputationGeneration

    let result = await Self.computeUserShiftsForMonthOffMain(
      .init(
        userId: userId,
        year: year,
        month: month,
        visibleRange: visibleRange,
        monthsInVisibleRange: monthsInVisibleRange,
        shifts: shifts,
        recurringShifts: recurringShifts,
        settings: settings,
        snapshots: snapshots,
        jobs: jobs
      )
    )

    guard generation == userShiftsComputationGeneration else { return }

    userShiftsForMonth = result.shifts
    userEarningsByDate = result.earningsByDate
    logger.info(
      "Loaded \(result.shifts.count) user shifts for superimpose visible range (\(year)-\(month))"
    )
  }

  /// Toggle superimpose mode and load user shifts if needed
  func toggleSuperimpose() {
    withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(duration: 0.4, bounce: 0.15)) {
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
    sharedShifts.contains(where: \.taxEnabled)
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

  /// Raw user shifts grouped by ISO date for precise overlap checks.
  var userShiftsByDate: [String: [ShiftRow]] {
    Dictionary(grouping: userShiftsForMonth, by: \.shift_date)
  }

  // MARK: - Private Methods

  private nonisolated static func convertSharedShiftsOffMain(_ shifts: [SharedShiftData]) async
    -> [ShiftWithComputations]
  {
    await Task.detached(priority: .userInitiated) {
      shifts.map { $0.toShiftWithComputations() }
    }.value
  }

  private nonisolated static func computeUserShiftsForMonthOffMain(
    _ input: UserShiftComputationInput
  ) async -> UserShiftComputationResult {
    await Task.detached(priority: .userInitiated) {
      var allShifts = input.shifts
      var realShiftKeys = Set(
        input.shifts.map { "\($0.shift_date)|\($0.start_time)|\($0.end_time)" })
      let startISO = input.visibleRange.start.toISODateString()
      let endISO = input.visibleRange.end.toISODateString()

      for recurring in input.recurringShifts {
        for (genYear, genMonth) in input.monthsInVisibleRange {
          let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
            year: genYear,
            month: genMonth,
            recurring: recurring
          )

          for virtual in virtualShifts {
            guard virtual.date >= startISO, virtual.date <= endISO else { continue }

            let key = "\(virtual.date)|\(recurring.cleanStartTime)|\(recurring.cleanEndTime)"
            if realShiftKeys.contains(key) { continue }
            realShiftKeys.insert(key)

            allShifts.append(
              ShiftRow(
                id: "virtual-\(recurring.id)-\(virtual.date)",
                user_id: recurring.user_id,
                shift_date: virtual.date,
                start_time: recurring.cleanStartTime,
                end_time: recurring.cleanEndTime,
                custom_pause_windows: recurring.date_specific_pause_windows?[virtual.date],
                custom_supplements: recurring.date_specific_supplements?[virtual.date],
                created_at: nil,
                recurring_id: recurring.id,
                recurring_anchor_weekday: virtual.weekday
              )
            )
          }
        }
      }

      let earningsByDate = Self.calculateUserEarningsByDate(
        shifts: allShifts,
        year: input.year,
        month: input.month,
        settings: input.settings,
        snapshots: input.snapshots,
        jobs: input.jobs
      )

      return UserShiftComputationResult(shifts: allShifts, earningsByDate: earningsByDate)
    }.value
  }

  private static func monthWindowForVisibleRange(year: Int, month: Int) -> [YearMonthKey] {
    let visibleRange = Date.visibleCalendarRange(year: year, month: month)
    return monthsInRange(startDate: visibleRange.start, endDate: visibleRange.end).map {
      YearMonthKey(year: $0.year, month: $0.month)
    }
  }

  private static func monthsInRange(startDate: Date, endDate: Date) -> [(year: Int, month: Int)] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone

    guard
      let startMonth = calendar.date(
        from: calendar.dateComponents([.year, .month], from: startDate)),
      let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate))
    else {
      return []
    }

    var result: [(year: Int, month: Int)] = []
    var current = startMonth

    while current <= endMonth {
      let components = calendar.dateComponents([.year, .month], from: current)
      if let year = components.year, let month = components.month {
        result.append((year: year, month: month))
      }
      guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: current) else {
        break
      }
      current = nextMonth
    }

    return result
  }

  private static func mergeSharedShifts(
    _ shiftSets: [[ShiftWithComputations]],
    visibleRange: (start: Date, end: Date)
  ) -> [ShiftWithComputations] {
    let startISO = visibleRange.start.toISODateString()
    let endISO = visibleRange.end.toISODateString()

    var seenIds = Set<String>()
    var merged: [ShiftWithComputations] = []

    for shifts in shiftSets {
      for shift in shifts where shift.shiftDate >= startISO && shift.shiftDate <= endISO {
        if seenIds.insert(shift.id).inserted {
          merged.append(shift)
        }
      }
    }

    return merged.sorted { lhs, rhs in
      if lhs.shiftDate == rhs.shiftDate {
        return lhs.startTime < rhs.startTime
      }
      return lhs.shiftDate < rhs.shiftDate
    }
  }

  private func fetchSharedShiftsForMonthWindow(
    ownerId: String,
    monthWindow: [YearMonthKey]
  ) async throws -> [YearMonthKey: SharedShiftsResponse] {
    switch monthWindow.count {
    case 0:
      return [:]

    case 1:
      let key = monthWindow[0]
      let response = try await sharingService.fetchSharedShifts(
        ownerId: ownerId,
        year: key.year,
        month: key.month
      )
      return [key: response]

    case 2:
      let key0 = monthWindow[0]
      let key1 = monthWindow[1]

      async let response0 = sharingService.fetchSharedShifts(
        ownerId: ownerId,
        year: key0.year,
        month: key0.month
      )
      async let response1 = sharingService.fetchSharedShifts(
        ownerId: ownerId,
        year: key1.year,
        month: key1.month
      )

      return [
        key0: try await response0,
        key1: try await response1,
      ]

    default:
      let key0 = monthWindow[0]
      let key1 = monthWindow[1]
      let key2 = monthWindow[2]

      async let response0 = sharingService.fetchSharedShifts(
        ownerId: ownerId,
        year: key0.year,
        month: key0.month
      )
      async let response1 = sharingService.fetchSharedShifts(
        ownerId: ownerId,
        year: key1.year,
        month: key1.month
      )
      async let response2 = sharingService.fetchSharedShifts(
        ownerId: ownerId,
        year: key2.year,
        month: key2.month
      )

      var responses: [YearMonthKey: SharedShiftsResponse] = [
        key0: try await response0,
        key1: try await response1,
        key2: try await response2,
      ]

      if monthWindow.count > 3 {
        for key in monthWindow.dropFirst(3) {
          responses[key] = try await sharingService.fetchSharedShifts(
            ownerId: ownerId,
            year: key.year,
            month: key.month
          )
        }
      }

      return responses
    }
  }

  private nonisolated static func calculateUserEarningsByDate(
    shifts: [ShiftRow],
    year: Int,
    month: Int,
    settings: UserSettings,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> [String: CalendarEarningsData] {
    guard !shifts.isEmpty else { return [:] }

    let computedShifts = PayrollEngine.computeShiftsForMonth(
      .init(
        year: year,
        month: month,
        shifts: shifts,
        recurring: [],
        snapshots: snapshots,
        settings: settings,
        jobs: jobs
      )
    )

    var netByDate: [String: Double] = [:]
    var grossByDate: [String: Double] = [:]
    var hasTaxByDate: [String: Bool] = [:]

    for shift in computedShifts {
      let net = shift.taxEnabled ? shift.netPay : shift.grossPay
      netByDate[shift.shiftDate, default: 0] += net
      grossByDate[shift.shiftDate, default: 0] += shift.grossPay
      hasTaxByDate[shift.shiftDate, default: false] =
        hasTaxByDate[shift.shiftDate, default: false] || shift.taxEnabled
    }

    var earningsByDate: [String: CalendarEarningsData] = [:]
    for (date, net) in netByDate {
      earningsByDate[date] = CalendarEarningsData(
        net: net,
        gross: grossByDate[date] ?? net,
        hasTaxEnabled: hasTaxByDate[date] ?? false
      )
    }

    return earningsByDate
  }

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
