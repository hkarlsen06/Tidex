// swiftlint:disable function_body_length
// Watch connectivity requires handling multiple delegate methods in sequence
import Foundation
import WatchConnectivity
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WatchConnectivity")
private let iphoneRefreshReplyTimeout = Duration.seconds(8)

private final class OneShotBoolContinuation: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Bool, Never>?

  init(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  @discardableResult
  func resume(returning value: () -> Bool) -> Bool {
    lock.lock()
    let continuation = continuation
    self.continuation = nil
    lock.unlock()

    guard let continuation else {
      return false
    }

    continuation.resume(returning: value())
    return true
  }
}

/// Manages Watch Connectivity for the watchOS app
/// Primary data source: Direct API fetch
/// Fallback: Receives shift data from the paired iPhone via applicationContext
@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
  static let shared = WatchConnectivityManager()

  private let shiftDataKey = "shiftData"
  private let refreshAction = "refresh"

  private(set) var isReachable = false
  private(set) var isRefreshing = false
  private(set) var lastRefreshFailed = false

  /// Whether a refresh is possible (either via API with valid token, or via iPhone)
  var canRefresh: Bool {
    isReachable || SharedKeychainStorage.hasValidToken
  }

  private override init() {
    super.init()
  }

  // MARK: - Session Activation

  /// Activate WCSession - call from app init
  func activateSession() {
    guard WCSession.isSupported() else {
      logger.info("WCSession not supported on this device")
      return
    }

    WCSession.default.delegate = self
    WCSession.default.activate()
    logger.info("WCSession activation requested")
  }

  // MARK: - Refresh Request

  /// Request fresh data - prefers iPhone (user + friends), falls back to API (friends only)
  func requestRefresh() {
    guard !isRefreshing else {
      logger.info("Refresh already in progress")
      return
    }

    isRefreshing = true
    lastRefreshFailed = false

    Task {
      // Prefer iPhone when reachable - it provides both user and friend data
      if WCSession.default.isReachable {
        logger.info("iPhone reachable - requesting full refresh")
        let iphoneSuccess = await requestRefreshFromiPhone()

        if iphoneSuccess {
          logger.info("iPhone refresh successful")
          // Ensure complications/widgets re-evaluate immediately after manual refresh.
          // When applicationContext delivery is delayed, this still forces a refresh
          // against the latest persisted payload.
          WidgetCenter.shared.reloadAllTimelines()
          isRefreshing = false
          return
        }
        // iPhone failed even though reachable - try API as fallback
        logger.info("iPhone request failed, trying API fallback")
      }

      // iPhone not reachable or failed - use API for friends data only
      // (preserves existing user shift data)
      let apiSuccess = await fetchFromAPI()

      if apiSuccess {
        logger.info("API refresh successful (friends only)")
        isRefreshing = false
        return
      }

      // Both failed
      lastRefreshFailed = true
      isRefreshing = false
      logger.warning("Refresh failed: iPhone not reachable and API unavailable")

      // Auto-clear error state after 3 seconds
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        self.lastRefreshFailed = false
      }
    }
  }

  // MARK: - Direct API Fetch

  /// Fetch friends data directly from API
  /// Returns true if successful, false if should fall back to iPhone
  private func fetchFromAPI() async -> Bool {
    do {
      let friends = try await FriendsAPIClient.fetchFriendsWithShifts()
      logger.info("API fetch successful: \(friends.count) friends")

      // Convert to WatchShiftDTO format
      let friendShifts = friends.compactMap { friend -> WatchShiftDTO? in
        guard friend.hasShift,
          let shiftId = friend.shiftId,
          let shiftDate = friend.shiftDate,
          let startTime = friend.startTime,
          let endTime = friend.endTime,
          let friendStatus = friend.status
        else {
          return nil
        }

        // Convert FriendShiftStatus to ShiftPreviewStatus
        let status: ShiftPreviewStatus
        switch friendStatus {
        case .active: status = .active
        case .upcoming: status = .upcoming
        case .past: status = .past
        }

        return WatchShiftDTO(
          id: shiftId,
          personId: friend.id,
          personName: friend.displayName,
          personProfilePictureUrl: friend.profilePictureUrl,
          personOauthAvatarUrl: friend.oauthAvatarUrl,
          shiftDate: shiftDate,
          startTime: startTime,
          endTime: endTime,
          status: status,
          avatarImageData: nil  // Watch will load from URL if needed
        )
      }

      // Create payload and update store
      // Preserve existing user shift since the friends API doesn't include it
      let payload = WatchDataPayload(
        timestamp: Date(),
        lastSyncTimestamp: Date(),
        userShift: WatchDataStore.shared.userShift,
        friendShifts: friendShifts,
        currencySymbol: WatchDataStore.shared.currencySymbol
      )

      WatchDataStore.shared.update(from: payload)
      return true

    } catch FriendsAPIError.noAccessToken {
      logger.info("No access token - need to authenticate on iPhone")
      return false
    } catch FriendsAPIError.unauthorized {
      logger.info("Token expired - need to refresh on iPhone")
      return false
    } catch {
      logger.error("API fetch failed: \(error.localizedDescription)")
      return false
    }
  }

  // MARK: - iPhone Fallback

  /// Request fresh data from iPhone (fallback when API fails)
  /// - Returns: true if refresh was successful, false if iPhone not reachable or request failed
  private func requestRefreshFromiPhone() async -> Bool {
    guard WCSession.default.isReachable else {
      logger.info("iPhone not reachable - cannot refresh from iPhone")
      isRefreshing = false
      return false
    }

    return await withCheckedContinuation { continuation in
      let reply = OneShotBoolContinuation(continuation)
      var timeoutTask: Task<Void, Never>?
      timeoutTask = Task { [weak self] in
        try? await Task.sleep(for: iphoneRefreshReplyTimeout)
        guard !Task.isCancelled else { return }

        if reply.resume(returning: { false }) {
          await MainActor.run {
            self?.isRefreshing = false
          }
          logger.warning("iPhone refresh timed out waiting for reply")
        }
      }

      WCSession.default.sendMessage(
        ["action": refreshAction],
        replyHandler: { [weak self] response in
          Task { @MainActor in
            timeoutTask?.cancel()

            guard let self else {
              reply.resume(returning: { false })
              return
            }

            reply.resume {
              self.isRefreshing = false
              logger.info("iPhone refresh response received: \(response)")

              // Store token locally if iPhone sent it
              // This enables direct API access on subsequent refreshes
              if let tokenInfo = response["token"] as? [String: Any],
                let accessToken = tokenInfo["accessToken"] as? String,
                let expiresAt = tokenInfo["expiresAt"] as? Int
              {
                do {
                  try SharedKeychainStorage.storeAccessToken(accessToken, expiresAt: expiresAt)
                  logger.info("Stored access token from iPhone (expires: \(expiresAt))")
                } catch {
                  logger.warning("Failed to store token from iPhone: \(error.localizedDescription)")
                }
              }

              guard response["success"] as? Bool == true else {
                let errorMessage = response["error"] as? String ?? "Unknown iPhone refresh error"
                logger.warning("iPhone refresh rejected: \(errorMessage)")
                return false
              }

              guard let data = response[self.shiftDataKey] as? Data else {
                logger.warning("iPhone refresh response missing payload")
                return false
              }

              return self.processReceivedData(data, source: "reply")
            }
          }
        },
        errorHandler: { [weak self] error in
          Task { @MainActor in
            timeoutTask?.cancel()
            reply.resume {
              self?.isRefreshing = false
              logger.error("iPhone refresh failed: \(error.localizedDescription)")
              return false
            }
          }
        }
      )
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
      if let error {
        logger.error("Activation failed: \(error.localizedDescription)")
      } else {
        logger.info("Activated: \(activationState.rawValue)")
        self?.isReachable = session.isReachable

        // Check for any existing application context
        if let data = session.receivedApplicationContext[self?.shiftDataKey ?? "shiftData"] as? Data
        {
          _ = self?.processReceivedData(data, source: "activation_context")
        }
      }
    }
  }

  nonisolated func session(
    _: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    Task { @MainActor [weak self] in
      guard let key = self?.shiftDataKey,
        let data = applicationContext[key] as? Data
      else {
        logger.warning("No shiftData in applicationContext")
        return
      }
      _ = self?.processReceivedData(data, source: "application_context")
    }
  }

  internal nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    Task { @MainActor [weak self] in
      guard let key = self?.shiftDataKey,
        let data = userInfo[key] as? Data
      else {
        logger.warning("No shiftData in userInfo transfer")
        return
      }
      _ = self?.processReceivedData(data, source: "user_info")
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in
      self?.isReachable = session.isReachable
      logger.info("Reachability changed: \(session.isReachable)")
    }
  }

  // MARK: - Private

  @discardableResult
  private func processReceivedData(_ data: Data, source: String) -> Bool {
    do {
      let payload = try JSONDecoder().decode(WatchDataPayload.self, from: data)
      WatchDataStore.shared.update(from: payload)
      logger.info(
        "Received data (\(source, privacy: .public)): user=\(payload.userShift != nil), friends=\(payload.friendShifts.count), bytes=\(data.count)"
      )
      return true
    } catch {
      logger.error(
        "Failed to decode payload (\(source, privacy: .public)): \(error.localizedDescription)")
      return false
    }
  }
}
// swiftlint:enable function_body_length
