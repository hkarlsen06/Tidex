import Foundation
import SwiftUI
import Supabase
import Combine
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

    // MARK: - Month Navigation (MonthNavigable)

    var displayYear: Int { monthContext.displayYear }
    var displayMonth: Int { monthContext.displayMonth }
    var isCurrentMonth: Bool { monthContext.isCurrentMonth }
    var displayMonthName: String { monthContext.displayMonthName }

    /// Required by MonthNavigable protocol
    var isLoading: Bool { isLoadingSharers || isLoadingShifts }

    // MARK: - Private State

    private var cachedUserId: String?
    private var monthContextCancellable: AnyCancellable?
    private var lastObservedYear: Int = 0
    private var lastObservedMonth: Int = 0

    // MARK: - Initialization

    init(
        sharingService: SharingService? = nil,
        sharedShiftsRepository: SharedShiftsRepository? = nil,
        monthContext: SharedMonthContext? = nil
    ) {
        self.sharingService = sharingService ?? SharingService.shared
        self.sharedShiftsRepository = sharedShiftsRepository ?? SharedShiftsRepository.shared
        self.monthContext = monthContext ?? SharedMonthContext.shared

        // Initialize tracking
        self.lastObservedYear = self.monthContext.displayYear
        self.lastObservedMonth = self.monthContext.displayMonth

        // Subscribe to month context changes
        setupMonthContextSubscription()
    }

    private func setupMonthContextSubscription() {
        monthContextCancellable = monthContext.monthChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMonth in
                guard let self = self else { return }

                guard newMonth.year != self.lastObservedYear || newMonth.month != self.lastObservedMonth else {
                    return
                }

                self.lastObservedYear = newMonth.year
                self.lastObservedMonth = newMonth.month
                self.navigationDirection = self.monthContext.navigationDirection

                // Reload shifts for new month if a sharer is selected
                if self.selectedSharer != nil {
                    Task {
                        await self.loadShiftsForSelectedSharer()
                    }
                }
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
                    logger.info("Loaded \(cachedSharers.count) sharers and \(cachedPreviews.count) previews from cache together")
                }
            }

            // Only show loading indicator if we have no cached data
            if !loadedFromCache && sharers.isEmpty {
                isLoadingSharers = true
            }

            // Fetch fresh data from network
            logger.info("Fetching fresh sharers from network...")
            let freshSharers = try await sharingService.fetchSharers(for: userId)
            logger.info("Network returned \(freshSharers.count) sharers: \(freshSharers.map { $0.displayName })")

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

            logger.info("Loaded shift previews for \(previews.count) sharers (forceRefresh: \(forceRefresh))")
        } catch {
            logger.error("Failed to load shift previews: \(error.localizedDescription)")
            // Don't set error - previews are non-critical
        }

        isLoadingPreviews = false
    }

    /// Refresh sharers (pull-to-refresh) - forces fresh data
    func refresh() async {
        if selectedSharer != nil {
            // Refresh shifts for selected sharer
            await loadShiftsForSelectedSharer()
        } else {
            // Refresh sharer list and previews with forced refresh
            await loadSharers(forceRefreshPreviews: true)
        }
    }

    /// Select a sharer to view their shifts
    func selectSharer(_ sharer: SharedUser) {
        selectedSharer = sharer
        sharedShifts = []

        Task {
            await loadShiftsForSelectedSharer()
        }
    }

    /// Go back to sharer list
    func deselectSharer() {
        selectedSharer = nil
        sharedShifts = []
        lastCacheTime = nil
    }

    /// Load shifts for the selected sharer and current month
    func loadShiftsForSelectedSharer() async {
        guard let sharer = selectedSharer else { return }

        error = nil

        do {
            guard let userId = try await getCurrentUserId() else {
                throw SharingError.notAuthenticated
            }

            let year = displayYear
            let month = displayMonth

            // Load from cache first (synchronously, before setting loading state)
            let cachedShifts = sharedShiftsRepository.getSharedShifts(
                ownerId: sharer.id,
                viewerId: userId,
                year: year,
                month: month
            )

            if !cachedShifts.isEmpty {
                // Cache hit - show cached data immediately, no loading flash
                sharedShifts = cachedShifts
                lastCacheTime = sharedShiftsRepository.getLastCacheTime(
                    ownerId: sharer.id,
                    viewerId: userId,
                    year: year,
                    month: month
                )
                // Don't set isLoadingShifts - we have data to show
            } else {
                // Cache miss - clear old data and show loading state
                // This prevents showing an empty calendar with old month's data
                sharedShifts = []
                isLoadingShifts = true
            }

            // Fetch fresh data from API
            let response = try await sharingService.fetchSharedShifts(
                ownerId: sharer.id,
                year: year,
                month: month
            )

            // Convert to ShiftWithComputations
            let freshShifts = response.shifts.map { $0.toShiftWithComputations() }
            sharedShifts = freshShifts
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

        } catch {
            logger.error("Failed to load shared shifts: \(error.localizedDescription)")
            self.error = SharingError.loadFailed(underlying: error)
        }

        isLoadingShifts = false
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

    // MARK: - Private Methods

    private func getCurrentUserId() async throws -> String? {
        if let cached = cachedUserId {
            return cached
        }

        let session = try await supabase.auth.session
        let userId = session.normalizedUserId
        cachedUserId = userId
        return userId
    }
}
