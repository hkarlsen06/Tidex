import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SharingService")

// MARK: - Shift Preview

/// Preview of a sharer's next/active/past shift
struct SharerShiftPreview: Equatable {
  let sharerId: String
  let shift: SharedShiftData?
  let status: ShiftPreviewStatus?
  let showEarnings: Bool
  let currency: String?
  let hasSharedCalendarContent: Bool

  init(
    sharerId: String,
    shift: SharedShiftData?,
    status: ShiftPreviewStatus?,
    showEarnings: Bool,
    currency: String?,
    hasSharedCalendarContent: Bool? = nil
  ) {
    self.sharerId = sharerId
    self.shift = shift
    self.status = status
    self.showEarnings = showEarnings
    self.currency = currency
    self.hasSharedCalendarContent = hasSharedCalendarContent ?? (shift != nil)
  }
}

// Note: ShiftPreviewStatus is now defined in Shared/ShiftPreviewStatus.swift
// for use by the app and extensions

// MARK: - Errors

enum SharingServiceError: Error, LocalizedError {
  case notAuthenticated
  case networkError(underlying: Error)
  case decodingError(underlying: Error)
  case httpError(statusCode: Int, message: String?)
  case noShareAccess

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return String(localized: .commonErrorNotAuthenticated)

    case .networkError:
      // Not the URLError text: it follows the system language, not the app language.
      return String(localized: .commonErrorGeneric)

    case .decodingError:
      return String(localized: .commonErrorUnexpectedResponse)

    case .httpError(_, let message):
      return message ?? String(localized: .commonErrorGeneric)

    case .noShareAccess:
      return String(localized: .sharingErrorNoShareAccess)
    }
  }
}

// MARK: - Cached Preview

/// Cached shift preview with timestamp
private struct CachedPreview {
  let preview: SharerShiftPreview
  let cachedAt: Date
}

struct FriendsTabBootstrapData {
  let sharers: [SharedUser]
  let friends: [Friend]
  let blockedFriends: [Friend]
  let previews: [SharerShiftPreview]

  var managementSnapshot: FriendsManagementSnapshot {
    FriendsManagementSnapshot(
      friends: friends,
      blockedFriends: blockedFriends
    )
  }
}

struct FriendsManagementSnapshot {
  let friends: [Friend]
  let blockedFriends: [Friend]
}

struct FriendsTabBootstrapRPCResponse: Decodable {
  let sharers: [SharedUser]
  let friends: [Friend]
  let blockedFriends: [Friend]?
  let previewPayloads: [SharingRPCPreviewPayloadRow]
}

// MARK: - Sharing Service

/// Service for fetching shared shifts and sharers.
/// Every call goes to the Convex `sharing` functions.
@MainActor
// swiftlint:disable:next type_body_length
final class SharingService {
  static let shared = SharingService()

  private(set) var sharers: [SharedUser] = []
  private(set) var isLoadingSharers = false
  private(set) var isLoadingShifts = false
  private(set) var error: Error?

  /// Cache for shift previews (by sharer ID)
  private var previewCache: [String: CachedPreview] = [:]

  /// Cache validity duration (5 minutes)
  private let previewCacheValiditySeconds: TimeInterval = 5 * 60

  private init() {}

  /// Get cached preview if still valid
  func getCachedPreview(for sharerId: String) -> SharerShiftPreview? {
    guard let cached = previewCache[sharerId] else { return nil }
    let age = Date().timeIntervalSince(cached.cachedAt)
    guard age < previewCacheValiditySeconds else {
      previewCache.removeValue(forKey: sharerId)
      return nil
    }
    return cached.preview
  }

  /// Clear all preview cache
  func clearPreviewCache() {
    previewCache.removeAll()
  }

  // MARK: - Sharer List

  /// Fetches the complete Friends tab bootstrap payload in one query.
  func fetchFriendsTabBootstrap() async throws -> FriendsTabBootstrapData {
    let now = Date()
    let startDate = SharingComputeCore.isoDateString(
      Calendar.gregorianCurrent.date(byAdding: .day, value: -30, to: now) ?? now)
    let endDate = SharingComputeCore.isoDateString(
      Calendar.gregorianCurrent.date(byAdding: .day, value: 30, to: now) ?? now)

    do {
      return try await loadFriendsTabBootstrap(startDate: startDate, endDate: endDate, now: now)
    } catch {
      throw mapRPCError(error)
    }
  }

  private func loadFriendsTabBootstrap(
    startDate: String,
    endDate: String,
    now: Date
  ) async throws -> FriendsTabBootstrapData {
    let params: [String: AnyJSON] = [
      "preview_start_date": .string(startDate),
      "preview_end_date": .string(endDate),
    ]

    let response: FriendsTabBootstrapRPCResponse = try await ConvexAPI.app.query(
      "sharing:friendsBootstrap", params)

    let payloadBySharerId = Dictionary(
      response.previewPayloads.map { ($0.sharerId, $0) },
      uniquingKeysWith: { _, last in last }
    )
    let sharerIds = response.sharers.map(\.id)
    let previews = await Self.computeShiftPreviewsOffMain(
      uncachedIds: sharerIds,
      payloadBySharerId: payloadBySharerId,
      startDate: startDate,
      endDate: endDate,
      now: now
    )

    for preview in previews {
      previewCache[preview.sharerId] = CachedPreview(preview: preview, cachedAt: now)
    }

    return FriendsTabBootstrapData(
      sharers: response.sharers,
      friends: response.friends,
      blockedFriends: response.blockedFriends ?? [],
      previews: previews
    )
  }

  /// Fetch users who have shared their shifts with the current user.
  func fetchSharers(for userId: String) async throws -> [SharedUser] {
    _ = userId  // Signature stability for existing callers
    isLoadingSharers = true
    error = nil
    defer { isLoadingSharers = false }

    return try await withTaskCancellationHandler {
      do {
        // Check for cancellation before making network request
        try Task.checkCancellation()

        let bootstrap = try await fetchFriendsTabBootstrap()
        try Task.checkCancellation()

        sharers = bootstrap.sharers
        logger.info("Loaded \(bootstrap.sharers.count) sharers for user")
        return bootstrap.sharers

      } catch is CancellationError {
        logger.info("Sharers fetch was cancelled")
        throw CancellationError()
      } catch {
        let mapped = mapRPCError(error)
        self.error = mapped
        throw mapped
      }
    } onCancel: {
      logger.info("Sharers fetch cancellation requested")
    }
  }

  // MARK: - Shared Shifts

  /// Fetch the shared shifts month payload and compute client-side.
  func fetchSharedShifts(
    ownerId: String,
    year: Int,
    month: Int
  ) async throws -> SharedShiftsResponse {
    isLoadingShifts = true
    error = nil
    defer { isLoadingShifts = false }

    return try await withTaskCancellationHandler {
      do {
        // Check for cancellation before making network request
        try Task.checkCancellation()

        let params: [String: AnyJSON] = [
          "owner_id": .string(ownerId),
          "year": .integer(year),
          "month": .integer(month),
        ]

        logger.info("Fetching shared month payload for owner \(ownerId, privacy: .private)")

        // Null means no share access or the share is hidden from the viewer.
        let result: SharingRPCMonthPayloadRow? = try await ConvexAPI.app.query(
          "sharing:sharedMonth", params)
        guard let payloadRow = result else { throw SharingServiceError.noShareAccess }

        // Check for cancellation after the query
        try Task.checkCancellation()

        let response = await Self.computeSharedShiftsResponseOffMain(
          payloadRow: payloadRow,
          year: year,
          month: month
        )

        logger.info("Loaded \(response.shifts.count) shared shifts for month \(year)-\(month)")
        return response

      } catch is CancellationError {
        logger.info("Shared shifts fetch was cancelled")
        throw CancellationError()
      } catch {
        let mapped = mapRPCError(error)
        self.error = mapped
        throw mapped
      }
    } onCancel: {
      logger.info("Shared shifts fetch cancellation requested")
    }
  }

  // MARK: - Shift Previews

  /// Fetch shift previews for all sharers
  /// Returns the most relevant shift (active > upcoming > past) for each sharer
  /// Uses cache for recently fetched previews (5 minute validity)
  func fetchShiftPreviews(sharerIds: [String], forceRefresh: Bool = false) async throws
    -> [SharerShiftPreview]
  {
    guard !sharerIds.isEmpty else { return [] }

    // Check cache first (unless force refresh)
    var cachedPreviews: [SharerShiftPreview] = []
    var uncachedIds: [String] = []

    if !forceRefresh {
      for sharerId in sharerIds {
        if let cached = getCachedPreview(for: sharerId) {
          cachedPreviews.append(cached)
        } else {
          uncachedIds.append(sharerId)
        }
      }

      // If all are cached, return immediately
      if uncachedIds.isEmpty {
        logger.info("Returning \(cachedPreviews.count) cached shift previews")
        return cachedPreviews
      }
    } else {
      uncachedIds = sharerIds
    }

    do {
      logger.info(
        "Fetching consolidated shift previews (needed: \(uncachedIds.count), cached: \(cachedPreviews.count))"
      )

      let uncachedIdSet = Set(uncachedIds)
      let freshPreviews = try await fetchFriendsTabBootstrap().previews.filter {
        uncachedIdSet.contains($0.sharerId)
      }

      // Merge cached + fresh and return
      let allPreviews = cachedPreviews + freshPreviews
      logger.info(
        "Loaded \(freshPreviews.count) fresh + \(cachedPreviews.count) cached shift previews")
      return allPreviews

    } catch {
      // If we have cached data, return it even on error
      if !cachedPreviews.isEmpty {
        logger.warning("Error, returning \(cachedPreviews.count) cached previews")
        return cachedPreviews
      }
      throw mapRPCError(error)
    }
  }

  // MARK: - Error Mapping

  private func mapRPCError(_ error: Error) -> SharingServiceError {
    if let serviceError = error as? SharingServiceError {
      return serviceError
    }

    if let failure = error as? ConvexAPI.Failure {
      switch failure {
      case .notSignedIn:
        return .notAuthenticated

      case .server(_, let message):
        return .httpError(statusCode: 400, message: message)

      case .badResponse(let status):
        return .httpError(statusCode: status, message: nil)
      }
    }

    if let decodingError = error as? DecodingError {
      return .decodingError(underlying: decodingError)
    }

    return .networkError(underlying: error)
  }

  private nonisolated static func mapComputedShiftToSharedShiftData(
    _ shift: SharingComputedShift
  ) -> SharedShiftData {
    SharedShiftData(
      id: shift.id,
      user_id: shift.userId,
      job_id: shift.jobId,
      job_name: shift.jobName,
      job_color: shift.jobColor,
      shift_date: shift.shiftDate,
      start_time: shift.startTime,
      end_time: shift.endTime,
      computed: SharedShiftComputed(
        id: shift.id,
        durationHours: shift.computed.durationHours,
        paidHours: shift.computed.paidHours,
        basePay: shift.computed.basePay,
        supplementPay: shift.computed.supplementPay,
        gross: shift.computed.gross,
        wagePeriods: mapWagePeriods(shift.computed.wagePeriods),
        originalWagePeriods: mapWagePeriods(shift.computed.originalWagePeriods),
        breakAudit: SharedBreakAudit(
          method: BreakMethod(rawValue: shift.computed.breakAudit.method.rawValue) ?? .none,
          thresholdHours: shift.computed.breakAudit.thresholdHours,
          deductedHours: shift.computed.breakAudit.deductedHours,
          source: shift.computed.breakAudit.source,
          appliedPauseWindows: shift.computed.breakAudit.appliedPauseWindows,
          notes: shift.computed.breakAudit.notes
        ),
        overtimeApplied: shift.computed.overtimeApplied,
        overtimeMinutes: shift.computed.overtimeMinutes
      ),
      tax_enabled: shift.taxEnabled,
      tax_percentage: shift.taxPercentage,
      custom_pause_windows: shift.customPauseWindows,
      custom_supplements: shift.customSupplements.map(mapCustomSupplements),
      recurring_id: shift.recurringId,
      recurring_anchor_weekday: shift.recurringAnchorWeekday
    )
  }

  private nonisolated static func mapCustomSupplements(_ supplements: SharingRPCCustomSupplements)
    -> CustomSupplementsData
  {
    CustomSupplementsData(
      rules: supplements.rules.map { rule in
        CustomSupplementRule(
          from: rule.from,
          to: rule.to,
          rate: rule.rate,
          percent: rule.percent,
          isCustom: rule.isCustom
        )
      }
    )
  }

  private nonisolated static func mapWagePeriods(_ periods: [SharingRPCWagePeriod])
    -> [WagePeriod]
  {
    periods.map {
      WagePeriod(
        fromMin: $0.fromMin,
        toMin: $0.toMin,
        baseRate: $0.baseRate,
        supplementRate: $0.supplementRate,
        isOvertime: $0.isOvertime
      )
    }
  }

  private nonisolated static func computeSharedShiftsResponseOffMain(
    payloadRow: SharingRPCMonthPayloadRow,
    year: Int,
    month: Int
  ) async -> SharedShiftsResponse {
    await Task.detached(priority: .userInitiated) {
      let mode: SharingRPCMode = payloadRow.showEarnings ? .visible : .hidden
      var computedShifts = SharingComputeCore.computeMonthShifts(
        payload: payloadRow.payloadInput,
        year: year,
        month: month,
        mode: mode
      )

      if !payloadRow.showEarnings {
        computedShifts = SharingComputeCore.enforceHiddenEarnings(on: computedShifts)
      }

      let shifts = computedShifts.map(Self.mapComputedShiftToSharedShiftData)
      let payoutTaxSettings = SharingComputeCore.payoutTaxSettings(
        year: year,
        month: month,
        settings: payloadRow.settings,
        snapshots: payloadRow.snapshots,
        jobs: payloadRow.jobs,
        mode: mode
      )
      .map { SharedPayoutTaxSettings(enabled: $0.enabled, percentage: $0.percentage) }

      return SharedShiftsResponse(
        shifts: shifts,
        settings: SharedUserSettings(
          payroll_day: payloadRow.settings.payrollDay,
          half_tax_month: payloadRow.settings.halfTaxMonth,
          monthly_goal: payloadRow.settings.monthlyGoal,
          monthly_goals_by_month: payloadRow.settings.monthlyGoalsByMonth,
          currency: payloadRow.settings.currency
        ),
        jobs: payloadRow.jobs.filter { $0.deletedAt == nil }.map {
          SharedJob(
            id: $0.id,
            user_id: $0.userId,
            name: $0.name,
            color: $0.color,
            currency: $0.currency,
            is_default: $0.isDefault,
            sort_order: $0.sortOrder,
            payroll_day: $0.payrollDay,
            half_tax_month: $0.halfTaxMonth,
            monthly_goal: $0.monthlyGoal
          )
        },
        payoutTaxSettings: payloadRow.showEarnings ? payoutTaxSettings : nil
      )
    }.value
  }

  private nonisolated static func computeShiftPreviewsOffMain(
    uncachedIds: [String],
    payloadBySharerId: [String: SharingRPCPreviewPayloadRow],
    startDate: String,
    endDate: String,
    now: Date
  ) async -> [SharerShiftPreview] {
    await Task.detached(priority: .userInitiated) {
      uncachedIds.map { sharerId in
        guard let payloadRow = payloadBySharerId[sharerId] else {
          return SharerShiftPreview(
            sharerId: sharerId,
            shift: nil,
            status: nil,
            showEarnings: false,
            currency: nil,
            hasSharedCalendarContent: false
          )
        }

        let hasSharedCalendarContent =
          !payloadRow.shifts.isEmpty
          || !payloadRow.recurringShifts.isEmpty

        let mode: SharingRPCMode = payloadRow.showEarnings ? .visible : .hidden
        var shifts = SharingComputeCore.computeShiftsInRange(
          payload: payloadRow.payloadInput,
          startDate: startDate,
          endDate: endDate,
          mode: mode
        )

        if !payloadRow.showEarnings {
          shifts = SharingComputeCore.enforceHiddenEarnings(on: shifts)
        }

        let preview = SharingComputeCore.selectPreview(
          sharerId: sharerId,
          shifts: shifts,
          showEarnings: payloadRow.showEarnings,
          now: now
        )
        let previewCurrency =
          preview.shift.flatMap { shift in
            payloadRow.jobs.first(where: { $0.id == shift.jobId })?.currency
          } ?? payloadRow.settings.currency

        return SharerShiftPreview(
          sharerId: sharerId,
          shift: preview.shift.map(Self.mapComputedShiftToSharedShiftData),
          status: preview.status.flatMap { ShiftPreviewStatus(rawValue: $0.rawValue) },
          showEarnings: preview.showEarnings,
          currency: previewCurrency,
          hasSharedCalendarContent: hasSharedCalendarContent
        )
      }
    }.value
  }

  // MARK: - Friends Management

  // Fetch all friends (bidirectional relationships) and blocked friends.
  // Used by the sharing management modal.
  // swiftlint:disable:next cyclomatic_complexity function_body_length type_contents_order
  internal func fetchAllFriends() async throws -> (
    friends: [Friend],
    blockedFriends: [Friend]
  ) {
    do {
      logger.info("Starting fetchAllFriends...")

      do {
        let bootstrap = try await fetchFriendsTabBootstrap()

        logger.info(
          """
          Loaded \(bootstrap.friends.count) friends and
          \(bootstrap.blockedFriends.count) blocked friends
          """
        )
        return (bootstrap.friends, bootstrap.blockedFriends)
      } catch let decodingError as DecodingError {
        // Log detailed decoding error info
        switch decodingError {
        case .keyNotFound(let key, let context):
          logger.error(
            """
            Decoding error - key not found: '\(key.stringValue)' at path: \
            \(context.codingPath.map(\.stringValue).joined(separator: "."))
            """
          )

        case .typeMismatch(let type, let context):
          logger.error(
            """
            Decoding error - type mismatch: expected \(type) at path: \
            \(context.codingPath.map(\.stringValue).joined(separator: "."))
            """
          )

        case .valueNotFound(let type, let context):
          logger.error(
            """
            Decoding error - value not found: \(type) at path: \
            \(context.codingPath.map(\.stringValue).joined(separator: "."))
            """
          )

        case .dataCorrupted(let context):
          logger.error(
            "Decoding error - data corrupted at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
          )

        @unknown default:
          logger.error("Decoding error - unknown: \(decodingError)")
        }
        throw SharingServiceError.decodingError(underlying: decodingError)
      } catch {
        logger.error("Failed to decode friends response: \(error)")
        throw SharingServiceError.decodingError(underlying: error)
      }

    } catch let error as SharingServiceError {
      logger.error("SharingServiceError in fetchAllFriends: \(error.localizedDescription)")
      throw error
    } catch {
      logger.error("Unexpected error in fetchAllFriends: \(error.localizedDescription)")
      throw SharingServiceError.networkError(underlying: error)
    }
  }

  // MARK: - Share Management Actions

  /// Create a new share by email or username. The server looks up the user and notifies them.
  func createShare(identifier: String, showEarnings: Bool = false) async throws {
    logger.info("Creating share")
    let params: [String: AnyJSON] = [
      "identifier": .string(identifier),
      "show_earnings": .bool(showEarnings),
    ]
    do {
      let result: ManageActionResponse = try await ConvexAPI.app.action(
        "sharing:createShare", params)
      try throwIfFailed(result)
    } catch {
      throw mapRPCError(error)
    }
    logger.info("Created share")
  }

  /// Remove a share (revoke recipient's access to my shifts)
  func removeShare(recipientId: String) async throws {
    logger.info("Removing share for recipient \(recipientId)")
    try await mutate("sharing:removeShare", ["viewer_id": .string(recipientId)])
    logger.info("Successfully removed share")
  }

  /// Remove a sharer from my friends list (as the viewer)
  func removeSharer(ownerId: String) async throws {
    logger.info("Removing sharer \(ownerId) from friends list")
    try await mutate("sharing:removeSharer", ["owner_id": .string(ownerId)])
    logger.info("Successfully removed sharer")
  }

  /// Toggle earnings visibility for a share recipient
  func toggleShareEarnings(recipientId: String, showEarnings: Bool) async throws {
    logger.info("Toggling earnings visibility for recipient \(recipientId) to \(showEarnings)")
    try await mutate(
      "sharing:updateMyShare",
      ["viewer_id": .string(recipientId), "show_earnings": .bool(showEarnings)]
    )
    logger.info("Successfully toggled earnings visibility")
  }

  /// Hide a sharer from the main list.
  func hideSharer(ownerId: String) async throws {
    logger.info("Hiding sharer \(ownerId)")
    try await mutate("sharing:updateSharer", ["owner_id": .string(ownerId), "hidden": .bool(true)])
    logger.info("Successfully hid sharer")
  }

  /// Show a previously hidden sharer in the main list.
  func showSharer(ownerId: String) async throws {
    logger.info("Showing sharer \(ownerId)")
    try await mutate("sharing:updateSharer", ["owner_id": .string(ownerId), "hidden": .bool(false)])
    logger.info("Successfully showed sharer")
  }

  /// Share back with someone who has shared with me
  func shareBack(recipientId: String) async throws {
    do {
      let result: ManageActionResponse = try await ConvexAPI.app.mutation(
        "sharing:shareBack", ["recipient_id": AnyJSON.string(recipientId)])
      try throwIfFailed(result)
    } catch {
      throw mapRPCError(error)
    }
  }

  /// Creates an abuse block for a user pair.
  func blockFriend(userId: String) async throws {
    logger.info("Blocking user pair \(userId, privacy: .private)")
    try await mutate("sharing:blockUser", ["other_user_id": .string(userId)])
    logger.info("Successfully blocked user pair")
  }

  /// Clears an abuse block for a user pair.
  func unblockFriend(userId: String) async throws {
    logger.info("Unblocking user pair \(userId, privacy: .private)")
    try await mutate("sharing:unblockUser", ["other_user_id": .string(userId)])
    logger.info("Successfully unblocked user pair")
  }

  /// Toggle muted status for a specific sharer
  func toggleSharerMuted(ownerId: String, muted: Bool) async throws {
    logger.info("Toggling muted status for sharer \(ownerId) to \(muted)")
    try await mutate("sharing:updateSharer", ["owner_id": .string(ownerId), "muted": .bool(muted)])
    logger.info("Successfully toggled muted status")
  }

  /// Toggle owner_muted status for a specific viewer
  func toggleOwnerMuted(viewerId: String, ownerMuted: Bool) async throws {
    logger.info("Toggling owner_muted for viewer \(viewerId) to \(ownerMuted)")
    try await mutate(
      "sharing:updateMyShare",
      ["viewer_id": .string(viewerId), "owner_muted": .bool(ownerMuted)]
    )
    logger.info("Successfully toggled owner_muted status")
  }

  // MARK: - Mutation Helpers

  /// Runs a mutation whose result the caller ignores and maps failures to `SharingServiceError`.
  private func mutate(_ path: String, _ params: [String: AnyJSON]) async throws {
    do {
      let _: ConvexAPI.Ignored = try await ConvexAPI.app.mutation(path, params)
    } catch {
      throw mapRPCError(error)
    }
  }

  private func throwIfFailed(_ result: ManageActionResponse) throws {
    guard result.success else {
      let errorMessage = result.error ?? "Unknown error"
      logger.error("Share action failed: \(errorMessage)")
      throw SharingServiceError.httpError(statusCode: 400, message: errorMessage)
    }
  }
  // swiftlint:disable:next file_length
}
