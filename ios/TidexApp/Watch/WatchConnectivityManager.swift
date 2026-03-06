import Foundation
import WatchConnectivity
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WatchConnectivityManager")

/// Manages Watch Connectivity for the iOS app
/// Sends shift data to the paired Apple Watch via applicationContext
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
  static let shared = WatchConnectivityManager()

  private let shiftDataKey = "shiftData"
  private let sentAtKey = "sentAt"
  private let maxContextPayloadBytes = 65_000
  private let maxReplyPayloadBytes = 45_000

  private var transferInFlight = false
  private var pendingUserIdForSync: String?
  private var pendingClearPayload = false
  private var pendingRetryTask: Task<Void, Never>?

  @Published private(set) var isWatchPaired = false
  @Published private(set) var isWatchAppInstalled = false

  override private init() {
    super.init()
  }

  // MARK: - Session Activation

  /// Activate WCSession - call from AppDelegate.didFinishLaunchingWithOptions
  func activateSession() {
    guard WCSession.isSupported() else {
      logger.info("WCSession not supported on this device")
      return
    }

    WCSession.default.delegate = self
    WCSession.default.activate()
    logger.info("WCSession activation requested")
  }

  // MARK: - Data Transfer

  /// Send updated shift data to Watch
  /// Gracefully handles cases where Watch is not available
  func sendUpdatedData(userId: String) {
    Task { @MainActor in
      _ = await sendUpdatedDataNow(userId: userId, reason: "scheduled_update")
    }
  }

  /// Send an explicit empty payload to clear stale Watch state (for sign-out/user switch).
  func sendClearedData() {
    Task { @MainActor in
      _ = sendClearedDataNow(reason: "scheduled_clear")
    }
  }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    Task { @MainActor [weak self] in
      if let error = error {
        logger.error("WCSession activation failed: \(error.localizedDescription)")
      } else {
        logger.info("WCSession activated: \(activationState.rawValue)")
        self?.updatePairingState(session)
        await self?.flushPendingTransferIfPossible()
      }
    }
  }

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    Task { @MainActor in
      logger.info("WCSession became inactive")
    }
  }

  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    Task { @MainActor in
      logger.info("WCSession deactivated")
      // Reactivate for multi-watch support
      session.activate()
    }
  }

  nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in
      self?.updatePairingState(session)
      await self?.flushPendingTransferIfPossible()
    }
  }

  /// Handle refresh request from Watch
  nonisolated func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    Task { @MainActor [weak self] in
      if message["action"] as? String == "refresh" {
        logger.info("Watch requested refresh")

        guard let self else {
          replyHandler(["success": false, "error": "Connectivity manager unavailable"])
          return
        }

        guard let userId = AppCoordinator.shared.userId else {
          replyHandler(["success": false, "error": "Not authenticated"])
          return
        }

        // Get the current session and include token in response
        // Note: Keychain access groups don't work iPhone↔Watch (separate devices)
        // so we send the token via WatchConnectivity for the Watch to store locally
        var tokenInfo: [String: Any] = [:]
        if let session = try? await AuthSessionManager.shared.getSession() {
          tokenInfo["accessToken"] = session.accessToken
          tokenInfo["expiresAt"] = session.expiresAt
        }

        // Trigger sync for user shifts
        _ = await SyncCoordinator.shared.sync(reason: .watchRefresh, userId: userId)

        // Also fetch friend data so it's available for the Watch
        await self.refreshFriendData(userId: userId)

        // Build payload once and send it through both channels:
        // - reply payload (strict immediate acknowledgement)
        // - applicationContext + transferUserInfo (background reliability)
        let payload = await WatchDataConverter.buildPayload(for: userId)
        guard let replyData = encodedPayloadData(payload, maxBytes: maxReplyPayloadBytes) else {
          replyHandler(["success": false, "error": "Failed to encode refresh payload"])
          return
        }

        let transferSucceeded = self.sendPayloadToWatch(
          payload, reason: "watch_refresh", maxPayloadBytes: maxContextPayloadBytes)

        var response: [String: Any] = [
          "success": true,
          "shiftData": replyData,
          "backgroundTransferQueued": transferSucceeded,
        ]
        if !transferSucceeded {
          response["warning"] = "Failed to queue payload transfer"
        }
        if !tokenInfo.isEmpty {
          response["token"] = tokenInfo
        }
        replyHandler(response)
      }
    }
  }

  // MARK: - Friend Data Refresh

  /// Fetch and cache friend data for Watch
  /// This ensures friend shifts are available even if user hasn't opened the sharing tab
  private func refreshFriendData(userId: String) async {
    do {
      // Fetch sharers from API
      let sharers = try await SharingService.shared.fetchSharers(for: userId)

      // Save to local cache
      await SharedShiftsRepository.shared.saveSharers(sharers, for: userId)

      // Get sharer IDs (non-blocked only)
      let sharerIds = sharers.filter { !$0.blocked }.map { $0.id }

      guard !sharerIds.isEmpty else {
        logger.info("No sharers to fetch previews for")
        return
      }

      // Fetch shift previews for all sharers
      let previews = try await SharingService.shared.fetchShiftPreviews(
        sharerIds: sharerIds,
        forceRefresh: true
      )

      // Save previews to local cache
      await SharedShiftsRepository.shared.saveShiftPreviews(previews, for: userId)

      logger.info(
        "Watch refresh: fetched \(sharers.count) sharers, \(previews.count) shift previews")
    } catch {
      logger.error("Watch refresh: failed to fetch friend data: \(error.localizedDescription)")
      // Continue anyway - we'll use whatever cached data is available
    }
  }

  // MARK: - Private

  private func updatePairingState(_ session: WCSession) {
    isWatchPaired = session.isPaired
    isWatchAppInstalled = session.isWatchAppInstalled
    logger.info("Watch state: paired=\(session.isPaired), installed=\(session.isWatchAppInstalled)")
  }

  private func isSessionReadyForTransfer(_ session: WCSession) -> Bool {
    session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
  }

  private func queueSync(for userId: String) {
    pendingUserIdForSync = userId
    schedulePendingRetry()
  }

  @discardableResult
  private func sendUpdatedDataNow(userId: String, reason: String) async -> Bool {
    guard WCSession.isSupported() else {
      return false
    }

    if transferInFlight {
      queueSync(for: userId)
      return false
    }

    let session = WCSession.default
    guard isSessionReadyForTransfer(session) else {
      queueSync(for: userId)
      logger.info("Watch transfer not ready - queued update for retry")
      return false
    }

    transferInFlight = true
    defer { transferInFlight = false }

    let payload = await WatchDataConverter.buildPayload(for: userId)
    let didSend = sendPayloadToWatch(
      payload, reason: reason, maxPayloadBytes: maxContextPayloadBytes)
    if didSend {
      if pendingUserIdForSync == userId {
        pendingUserIdForSync = nil
      }
      if pendingClearPayload || pendingUserIdForSync != nil {
        schedulePendingRetry()
      } else {
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
      }
    } else {
      queueSync(for: userId)
    }
    return didSend
  }

  @discardableResult
  private func sendClearedDataNow(reason: String) -> Bool {
    guard WCSession.isSupported() else {
      return false
    }

    if transferInFlight {
      pendingClearPayload = true
      pendingUserIdForSync = nil
      schedulePendingRetry()
      return false
    }

    let session = WCSession.default
    guard isSessionReadyForTransfer(session) else {
      pendingClearPayload = true
      pendingUserIdForSync = nil
      logger.info("Watch transfer not ready - queued clear payload for retry")
      schedulePendingRetry()
      return false
    }

    transferInFlight = true
    defer { transferInFlight = false }

    let clearPayload = WatchDataPayload(
      timestamp: Date(),
      lastSyncTimestamp: nil,
      userShift: nil,
      friendShifts: [],
      currencySymbol: "kr"
    )

    let didSend = sendPayloadToWatch(
      clearPayload, reason: reason, maxPayloadBytes: maxContextPayloadBytes)
    if didSend {
      pendingClearPayload = false
      if pendingUserIdForSync != nil {
        schedulePendingRetry()
      } else {
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
      }
    } else {
      pendingClearPayload = true
      schedulePendingRetry()
    }
    return didSend
  }

  @discardableResult
  private func sendPayloadToWatch(
    _ payload: WatchDataPayload,
    reason: String,
    maxPayloadBytes: Int
  ) -> Bool {
    let session = WCSession.default
    guard isSessionReadyForTransfer(session) else {
      return false
    }

    guard let data = encodedPayloadData(payload, maxBytes: maxPayloadBytes) else {
      logger.error("Failed to encode Watch payload within size limit")
      return false
    }

    let envelope: [String: Any] = [
      shiftDataKey: data,
      sentAtKey: Date().timeIntervalSince1970,
    ]

    do {
      try session.updateApplicationContext(envelope)
      session.transferUserInfo(envelope)
      queueComplicationTransferIfPossible(envelope, session: session, reason: reason)
      logger.info(
        "Sent Watch update (\(reason, privacy: .public)): user=\(payload.userShift != nil), friends=\(payload.friendShifts.count), bytes=\(data.count)"
      )
      return true
    } catch {
      logger.error(
        "Failed to send Watch payload (\(reason, privacy: .public)): \(error.localizedDescription)")
      return false
    }
  }

  private func encodedPayloadData(_ payload: WatchDataPayload, maxBytes: Int) -> Data? {
    // Always send compact transport payload and rely on URL fallback for avatars on watch.
    var candidate = compactPayload(payload)

    guard var encoded = try? JSONEncoder().encode(candidate) else {
      return nil
    }

    if encoded.count <= maxBytes {
      return encoded
    }

    // If still too large (many friends), trim low-priority tail entries until it fits.
    while !candidate.friendShifts.isEmpty && encoded.count > maxBytes {
      candidate = WatchDataPayload(
        timestamp: candidate.timestamp,
        lastSyncTimestamp: candidate.lastSyncTimestamp,
        userShift: candidate.userShift,
        friendShifts: Array(candidate.friendShifts.dropLast()),
        currencySymbol: candidate.currencySymbol
      )

      guard let trimmedData = try? JSONEncoder().encode(candidate) else {
        continue
      }
      encoded = trimmedData
    }

    if encoded.count <= maxBytes {
      logger.warning("Trimmed friend shifts to fit Watch payload budget (\(encoded.count) bytes)")
      return encoded
    }

    // Final fallback: send only the current user shift.
    let fallback = WatchDataPayload(
      timestamp: candidate.timestamp,
      lastSyncTimestamp: candidate.lastSyncTimestamp,
      userShift: candidate.userShift,
      friendShifts: [],
      currencySymbol: candidate.currencySymbol
    )

    guard let fallbackData = try? JSONEncoder().encode(fallback),
      fallbackData.count <= maxBytes
    else {
      return nil
    }
    logger.warning("Using fallback Watch payload (user shift only) to stay within size budget")
    return fallbackData
  }

  private func queueComplicationTransferIfPossible(
    _ envelope: [String: Any],
    session: WCSession,
    reason: String
  ) {
    guard session.remainingComplicationUserInfoTransfers > 0 else {
      logger.info(
        "Skipping complication transfer (\(reason, privacy: .public)): no remaining budget")
      return
    }

    session.transferCurrentComplicationUserInfo(envelope)
    logger.info(
      "Queued complication transfer (\(reason, privacy: .public)); remaining budget=\(session.remainingComplicationUserInfoTransfers)"
    )
  }

  private func compactPayload(_ payload: WatchDataPayload) -> WatchDataPayload {
    WatchDataPayload(
      timestamp: payload.timestamp,
      lastSyncTimestamp: payload.lastSyncTimestamp,
      userShift: stripAvatar(payload.userShift),
      friendShifts: payload.friendShifts.map(stripAvatar),
      currencySymbol: payload.currencySymbol
    )
  }

  private func stripAvatar(_ shift: WatchShiftDTO?) -> WatchShiftDTO? {
    guard let shift else { return nil }
    return stripAvatar(shift)
  }

  private func stripAvatar(_ shift: WatchShiftDTO) -> WatchShiftDTO {
    WatchShiftDTO(
      id: shift.id,
      personId: shift.personId,
      personName: shift.personName,
      personProfilePictureUrl: shift.personProfilePictureUrl,
      personOauthAvatarUrl: shift.personOauthAvatarUrl,
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      status: shift.status,
      avatarImageData: nil
    )
  }

  private func flushPendingTransferIfPossible() async {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard isSessionReadyForTransfer(session) else { return }

    if pendingClearPayload {
      _ = sendClearedDataNow(reason: "retry_clear")
      return
    }

    if let pendingUserIdForSync {
      _ = await sendUpdatedDataNow(userId: pendingUserIdForSync, reason: "retry_update")
    }
  }

  private func schedulePendingRetry() {
    pendingRetryTask?.cancel()
    pendingRetryTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard let self, !Task.isCancelled else { return }
      await self.flushPendingTransferIfPossible()
    }
  }
}
