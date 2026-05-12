import Auth
import Combine
import Foundation
import Supabase
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
// for use by both iOS and Watch targets

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
      return "Not authenticated"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .decodingError(let error):
      return "Failed to decode response: \(error.localizedDescription)"
    case .httpError(let code, let message):
      return "HTTP \(code): \(message ?? "Unknown error")"
    case .noShareAccess:
      return "No access to shared shifts"
    }
  }
}

// MARK: - Cached Preview

/// Cached shift preview with timestamp
private struct CachedPreview {
  let preview: SharerShiftPreview
  let cachedAt: Date
}

private struct IncomingBlockedShareRow: Decodable {
  let owner_id: String
  let blocked_by_user_id: String?
}

private struct OutgoingBlockedShareRow: Decodable {
  let viewer_id: String
  let blocked_by_user_id: String?
}

// MARK: - Sharing Service

/// Service for fetching shared shifts and sharers.
/// Sharing management now uses authenticated Supabase RPCs end-to-end.
@MainActor
final class SharingService: ObservableObject {
  static let shared = SharingService()

  @Published private(set) var sharers: [SharedUser] = []
  @Published private(set) var isLoadingSharers = false
  @Published private(set) var isLoadingShifts = false
  @Published private(set) var error: Error?

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

  // MARK: - Sharer List (via Supabase RPC)

  /// Fetch users who have shared their shifts with the current user
  /// Uses Supabase RPC get_my_sharers()
  func fetchSharers(for userId: String) async throws -> [SharedUser] {
    _ = userId  // Signature stability for existing callers
    isLoadingSharers = true
    error = nil
    defer { isLoadingSharers = false }

    return try await withTaskCancellationHandler {
      do {
        // Check for cancellation before making network request
        try Task.checkCancellation()

        // Ensure we have a valid authenticated Supabase session.
        _ = try await AuthSessionManager.shared.getSession()

        // Execute RPC
        let rpcRows: [SharingRPCSharerRow] =
          try await supabase
          .rpc("get_my_sharers")
          .execute()
          .value

        // Check for cancellation after RPC
        try Task.checkCancellation()

        // Map to SharedUser
        let users = rpcRows.map { sharer in
          SharedUser(
            id: sharer.id,
            email: sharer.email,
            phone: sharer.phone,
            username: sharer.username,
            firstName: sharer.firstName,
            profilePictureUrl: sharer.profilePictureUrl,
            oauthAvatarUrl: sharer.oauthAvatarUrl,
            sharedAt: sharer.sharedAt,
            showEarnings: sharer.showEarnings,
            hidden: sharer.hidden,
            hasSharedCalendarContent: sharer.hasSharedCalendarContent,
            latestSharedShiftDate: sharer.latestSharedShiftDate,
            hasRecurringSharedShifts: sharer.hasRecurringSharedShifts
          )
        }

        sharers = users
        logger.info("Loaded \(users.count) sharers for user")
        return users

      } catch let error as SharingServiceError {
        self.error = error
        throw error
      } catch let error as PostgrestError {
        let mapped = mapRPCError(error)
        self.error = mapped
        throw mapped
      } catch let error as AuthError {
        let mapped = mapRPCError(error)
        self.error = mapped
        throw mapped
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

  // MARK: - Shared Shifts (via Supabase RPC)

  /// Fetch shared shifts month payload from Supabase RPC and compute client-side.
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

        // Ensure we have a valid authenticated Supabase session.
        _ = try await AuthSessionManager.shared.getSession()

        let params: [String: AnyJSON] = [
          "p_owner_id": .string(ownerId),
          "p_year": .integer(year),
          "p_month": .integer(month),
        ]

        logger.info("Fetching shared month payload via RPC for owner \(ownerId, privacy: .private)")

        let payloadRow: SharingRPCMonthPayloadRow
        do {
          payloadRow =
            try await supabase
            .rpc("get_shared_month_payload", params: params)
            .single()
            .execute()
            .value
        } catch let postgrestError as PostgrestError where postgrestError.code == "PGRST116" {
          // No row means no share access or the share is hidden from the viewer.
          throw SharingServiceError.noShareAccess
        }

        // Check for cancellation after RPC
        try Task.checkCancellation()

        let response = await Self.computeSharedShiftsResponseOffMain(
          payloadRow: payloadRow,
          year: year,
          month: month
        )

        logger.info("Loaded \(response.shifts.count) shared shifts for month \(year)-\(month)")
        return response

      } catch let error as SharingServiceError {
        self.error = error
        throw error
      } catch let error as PostgrestError {
        let mapped = mapRPCError(error)
        self.error = mapped
        throw mapped
      } catch let error as AuthError {
        let mapped = mapRPCError(error)
        self.error = mapped
        throw mapped
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

  // MARK: - Shift Previews (via Supabase RPC)

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
      // Ensure we have a valid authenticated Supabase session.
      _ = try await AuthSessionManager.shared.getSession()

      let now = Date()
      let startDate = SharingComputeCore.isoDateString(
        Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now)
      let endDate = SharingComputeCore.isoDateString(
        Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now)

      let params: [String: AnyJSON] = [
        "p_sharer_ids": .array(uncachedIds.map { .string($0) }),
        "p_start_date": .string(startDate),
        "p_end_date": .string(endDate),
      ]

      logger.info(
        "Fetching \(uncachedIds.count) shift preview payloads via RPC (cached: \(cachedPreviews.count))"
      )

      let payloadRows: [SharingRPCPreviewPayloadRow] =
        try await supabase
        .rpc("get_my_sharer_preview_payloads", params: params)
        .execute()
        .value

      let payloadBySharerId = Dictionary(
        payloadRows.map { ($0.sharerId, $0) }, uniquingKeysWith: { _, last in last }
      )

      let freshPreviews = await Self.computeShiftPreviewsOffMain(
        uncachedIds: uncachedIds,
        payloadBySharerId: payloadBySharerId,
        startDate: startDate,
        endDate: endDate,
        now: now
      )

      // Cache the fresh previews
      for preview in freshPreviews {
        previewCache[preview.sharerId] = CachedPreview(preview: preview, cachedAt: now)
      }

      // Merge cached + fresh and return
      let allPreviews = cachedPreviews + freshPreviews
      logger.info(
        "Loaded \(freshPreviews.count) fresh + \(cachedPreviews.count) cached shift previews")
      return allPreviews

    } catch let error as SharingServiceError {
      // If we have cached data, return it even on error
      if !cachedPreviews.isEmpty {
        logger.warning("API error, returning \(cachedPreviews.count) cached previews")
        return cachedPreviews
      }
      throw error
    } catch let error as PostgrestError {
      if !cachedPreviews.isEmpty {
        logger.warning("RPC error, returning \(cachedPreviews.count) cached previews")
        return cachedPreviews
      }
      throw mapRPCError(error)
    } catch let error as AuthError {
      if !cachedPreviews.isEmpty {
        logger.warning("Auth error, returning \(cachedPreviews.count) cached previews")
        return cachedPreviews
      }
      throw mapRPCError(error)
    } catch {
      // If we have cached data, return it even on error
      if !cachedPreviews.isEmpty {
        logger.warning("Network error, returning \(cachedPreviews.count) cached previews")
        return cachedPreviews
      }
      throw mapRPCError(error)
    }
  }

  // MARK: - RPC Helpers

  private func mapRPCError(_ error: Error) -> SharingServiceError {
    if error is AuthError {
      return .notAuthenticated
    }

    if let postgrestError = error as? PostgrestError {
      let message = postgrestError.message
      let lowercasedMessage = message.lowercased()
      let code = (postgrestError.code ?? "").uppercased()

      if code == "PGRST301"
        || lowercasedMessage.contains("jwt")
        || lowercasedMessage.contains("unauthorized")
      {
        return .notAuthenticated
      }

      return .httpError(statusCode: 400, message: message)
    }

    if let decodingError = error as? DecodingError {
      return .decodingError(underlying: decodingError)
    }

    return .networkError(underlying: error)
  }

  private func fetchBlockedUserSets(for userId: String) async throws -> (
    allBlockedPairIds: Set<String>,
    blockedByCurrentUserIds: Set<String>
  ) {
    let incomingShares: [IncomingBlockedShareRow] =
      try await supabase
      .from("shift_shares")
      .select("owner_id, blocked_by_user_id")
      .eq("viewer_id", value: userId)
      .execute()
      .value

    let outgoingShares: [OutgoingBlockedShareRow] =
      try await supabase
      .from("shift_shares")
      .select("viewer_id, blocked_by_user_id")
      .eq("owner_id", value: userId)
      .execute()
      .value

    var allBlockedPairIds = Set<String>()
    var blockedByCurrentUserIds = Set<String>()

    for share in incomingShares where share.blocked_by_user_id != nil {
      allBlockedPairIds.insert(share.owner_id)
      if share.blocked_by_user_id == userId {
        blockedByCurrentUserIds.insert(share.owner_id)
      }
    }

    for share in outgoingShares where share.blocked_by_user_id != nil {
      allBlockedPairIds.insert(share.viewer_id)
      if share.blocked_by_user_id == userId {
        blockedByCurrentUserIds.insert(share.viewer_id)
      }
    }

    return (allBlockedPairIds, blockedByCurrentUserIds)
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
        breakAudit: SharedBreakAudit(
          method: BreakMethod(rawValue: shift.computed.breakAudit.method.rawValue) ?? .none,
          thresholdHours: shift.computed.breakAudit.thresholdHours,
          deductedHours: shift.computed.breakAudit.deductedHours,
          source: shift.computed.breakAudit.source,
          appliedPauseWindows: shift.computed.breakAudit.appliedPauseWindows,
          notes: shift.computed.breakAudit.notes
        )
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

  // MARK: - Friends Management (via Supabase RPC)

  /// Fetch all friends (bidirectional relationships) and share capacity
  /// Used by the sharing management modal
  func fetchAllFriends() async throws -> (
    friends: [Friend],
    blockedFriends: [Friend],
    capacity: ShareCapacity
  ) {
    do {
      logger.info("Starting fetchAllFriends...")
      let session = try await AuthSessionManager.shared.getSession()
      let userId = session.normalizedUserId
      logger.info("Got session, token expires at: \(session.expiresAt)")

      do {
        let apiResponse: FriendsAPIResponse =
          try await supabase
          .rpc("get_sharing_friends_api")
          .single()
          .execute()
          .value
        let blockedSets = try? await fetchBlockedUserSets(for: userId)
        let allBlockedPairIds = blockedSets?.allBlockedPairIds ?? Set<String>()
        let blockedByCurrentUserIds = blockedSets?.blockedByCurrentUserIds ?? Set<String>()

        let sanitizedFriends = apiResponse.friends.filter { !allBlockedPairIds.contains($0.id) }
        let apiBlockedFriends = (apiResponse.blockedFriends ?? []).filter {
          blockedByCurrentUserIds.contains($0.id)
        }
        let blockedFriendsFromFriends = apiResponse.friends.filter {
          blockedByCurrentUserIds.contains($0.id)
        }

        var mergedBlockedFriendsById: [String: Friend] = [:]
        for friend in apiBlockedFriends {
          mergedBlockedFriendsById[friend.id] = friend
        }
        for friend in blockedFriendsFromFriends {
          mergedBlockedFriendsById[friend.id] = friend
        }

        let mergedBlockedFriends = mergedBlockedFriendsById.values.sorted {
          $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        logger.info(
          """
          Loaded \(sanitizedFriends.count) friends and
          \(mergedBlockedFriends.count) blocked friends
          (capacity: \(apiResponse.capacity.currentCount)/\(apiResponse.capacity.limit))
          """
        )
        return (sanitizedFriends, mergedBlockedFriends, apiResponse.capacity)
      } catch let error as PostgrestError {
        throw mapRPCError(error)
      } catch let error as AuthError {
        throw mapRPCError(error)
      } catch let decodingError as DecodingError {
        // Log detailed decoding error info
        switch decodingError {
        case .keyNotFound(let key, let context):
          logger.error(
            "Decoding error - key not found: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
          )
        case .typeMismatch(let type, let context):
          logger.error(
            "Decoding error - type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
          )
        case .valueNotFound(let type, let context):
          logger.error(
            "Decoding error - value not found: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
          )
        case .dataCorrupted(let context):
          logger.error(
            "Decoding error - data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
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

  /// Action types for the manage endpoint
  enum ManageAction: String, Encodable {
    case createShare
    case removeShare
    case removeSharer
    case toggleEarnings
    case blockSharer
    case unblockSharer
    case shareBack
    case toggleMuted
  }

  /// Generic method to call the manage_sharing_action RPC.
  private func performManageAction(
    action: ManageAction,
    identifier: String? = nil,
    recipientId: String? = nil,
    ownerId: String? = nil,
    showEarnings: Bool? = nil,
    muted: Bool? = nil
  ) async throws {
    _ = try await AuthSessionManager.shared.getSession()

    var params: [String: AnyJSON] = [
      "p_action": .string(action.rawValue)
    ]
    if let identifier {
      params["p_identifier"] = .string(identifier)
    }
    if let recipientId {
      params["p_recipient_id"] = .string(recipientId)
    }
    if let showEarnings {
      params["p_show_earnings"] = .bool(showEarnings)
    }
    _ = ownerId
    _ = muted

    logger.info("Performing manage action: \(action.rawValue)")
    let result: ManageActionResponse =
      try await supabase
      .rpc("manage_sharing_action", params: params)
      .single()
      .execute()
      .value

    if !result.success {
      let errorMessage = result.error ?? "Unknown error"
      logger.error("Manage action failed: \(errorMessage)")
      throw SharingServiceError.httpError(statusCode: 400, message: errorMessage)
    }

    logger.info("Manage action \(action.rawValue) succeeded")
  }

  /// Create a new share by email, phone, or username
  /// Requires API for user lookup, limit checks, and notifications
  func createShare(identifier: String, showEarnings: Bool = false) async throws {
    try await performManageAction(
      action: .createShare,
      identifier: identifier,
      showEarnings: showEarnings
    )
  }

  /// Remove a share (revoke recipient's access to my shifts)
  /// Owner can delete directly via Supabase (RLS allows this)
  func removeShare(recipientId: String) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId

    logger.info("Removing share for recipient \(recipientId)")

    try await supabase
      .from("shift_shares")
      .delete()
      .eq("owner_id", value: userId)
      .eq("viewer_id", value: recipientId)
      .execute()

    logger.info("Successfully removed share")
  }

  /// Remove a sharer from my friends list (as the viewer)
  /// Viewer can delete directly via Supabase (RLS allows this)
  func removeSharer(ownerId: String) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId

    logger.info("Removing sharer \(ownerId) from friends list")

    try await supabase
      .from("shift_shares")
      .delete()
      .eq("owner_id", value: ownerId)
      .eq("viewer_id", value: userId)
      .execute()

    logger.info("Successfully removed sharer")
  }

  /// Toggle earnings visibility for a share recipient
  /// Owner can update show_earnings directly via Supabase (RLS allows this)
  func toggleShareEarnings(recipientId: String, showEarnings: Bool) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId

    logger.info("Toggling earnings visibility for recipient \(recipientId) to \(showEarnings)")

    try await supabase
      .from("shift_shares")
      .update(["show_earnings": showEarnings])
      .eq("owner_id", value: userId)
      .eq("viewer_id", value: recipientId)
      .execute()

    logger.info("Successfully toggled earnings visibility")
  }

  /// Hide a sharer from the main list.
  func hideSharer(ownerId: String) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId

    logger.info("Hiding sharer \(ownerId)")

    try await supabase
      .from("shift_shares")
      .update(["hidden": true])
      .eq("owner_id", value: ownerId)
      .eq("viewer_id", value: userId)
      .execute()

    logger.info("Successfully hid sharer")
  }

  /// Show a previously hidden sharer in the main list.
  func showSharer(ownerId: String) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId

    logger.info("Showing sharer \(ownerId)")

    try await supabase
      .from("shift_shares")
      .update(["hidden": false])
      .eq("owner_id", value: ownerId)
      .eq("viewer_id", value: userId)
      .execute()

    logger.info("Successfully showed sharer")
  }

  /// Share back with someone who has shared with me
  /// Requires API for limit checks and notifications
  func shareBack(recipientId: String) async throws {
    try await performManageAction(
      action: .shareBack,
      recipientId: recipientId
    )
  }

  /// Creates an abuse block for a user pair.
  func blockFriend(userId: String) async throws {
    let params: [String: AnyJSON] = [
      "p_other_user_id": .string(userId)
    ]

    logger.info("Blocking user pair \(userId, privacy: .private)")

    do {
      _ = try await AuthSessionManager.shared.getSession()

      _ =
        try await supabase
        .rpc("block_user_pair", params: params)
        .execute()

      logger.info("Successfully blocked user pair")
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw SharingServiceError.decodingError(underlying: error)
    } catch {
      throw SharingServiceError.networkError(underlying: error)
    }
  }

  /// Clears an abuse block for a user pair.
  func unblockFriend(userId: String) async throws {
    let params: [String: AnyJSON] = [
      "p_other_user_id": .string(userId)
    ]

    logger.info("Unblocking user pair \(userId, privacy: .private)")

    do {
      _ = try await AuthSessionManager.shared.getSession()

      _ =
        try await supabase
        .rpc("unblock_user_pair", params: params)
        .execute()

      logger.info("Successfully unblocked user pair")
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw SharingServiceError.decodingError(underlying: error)
    } catch {
      throw SharingServiceError.networkError(underlying: error)
    }
  }

  /// Toggle muted status for a specific sharer
  /// Viewer can update muted directly via Supabase (RLS allows this)
  func toggleSharerMuted(ownerId: String, muted: Bool) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId

    logger.info("Toggling muted status for sharer \(ownerId) to \(muted)")

    try await supabase
      .from("shift_shares")
      .update(["muted": muted])
      .eq("owner_id", value: ownerId)
      .eq("viewer_id", value: userId)
      .execute()

    logger.info("Successfully toggled muted status")
  }

  /// Toggle owner_muted status for a specific viewer
  /// Owner can update owner_muted directly via Supabase (RLS allows this)
  func toggleOwnerMuted(viewerId: String, ownerMuted: Bool) async throws {
    let session = try await AuthSessionManager.shared.getSession()
    let userId = session.normalizedUserId

    logger.info("Toggling owner_muted for viewer \(viewerId) to \(ownerMuted)")

    try await supabase
      .from("shift_shares")
      .update(["owner_muted": ownerMuted])
      .eq("owner_id", value: userId)
      .eq("viewer_id", value: viewerId)
      .execute()

    logger.info("Successfully toggled owner_muted status")
  }
}
