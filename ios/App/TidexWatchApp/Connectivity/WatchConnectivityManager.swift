import Foundation
import WatchConnectivity
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WatchConnectivity")

/// Manages Watch Connectivity for the watchOS app
/// Primary data source: Direct API fetch
/// Fallback: Receives shift data from the paired iPhone via applicationContext
@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    private(set) var isReachable = false
    private(set) var isRefreshing = false

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

    /// Request fresh data - tries API first, falls back to iPhone
    func requestRefresh() {
        guard !isRefreshing else {
            logger.info("Refresh already in progress")
            return
        }

        isRefreshing = true

        Task {
            // Try API first (standard approach)
            let apiSuccess = await fetchFromAPI()

            if apiSuccess {
                logger.info("API refresh successful")
                isRefreshing = false
                return
            }

            // API failed - fall back to iPhone
            logger.info("API failed, falling back to iPhone")
            await requestRefreshFromiPhone()
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
                    avatarImageData: nil // Watch will load from URL if needed
                )
            }

            // Create payload and update store
            let payload = WatchDataPayload(
                timestamp: Date(),
                lastSyncTimestamp: Date(),
                userShift: nil, // User's own shift not available via this API
                friendShifts: friendShifts,
                locale: getWatchLocale(),
                currencySymbol: "kr" // Default, could be stored in App Group
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

    /// Get the watch's locale preference
    private func getWatchLocale() -> String {
        if let preferred = Bundle.main.preferredLocalizations.first {
            if preferred.hasPrefix("nb") || preferred.hasPrefix("no") || preferred.hasPrefix("nn") {
                return "no"
            }
        }
        return "en"
    }

    // MARK: - iPhone Fallback

    /// Request fresh data from iPhone (fallback when API fails)
    private func requestRefreshFromiPhone() async {
        guard WCSession.default.isReachable else {
            logger.info("iPhone not reachable - cannot refresh from iPhone")
            isRefreshing = false
            return
        }

        return await withCheckedContinuation { continuation in
            WCSession.default.sendMessage(
                ["action": "refresh"],
                replyHandler: { [weak self] response in
                    Task { @MainActor in
                        self?.isRefreshing = false
                        logger.info("iPhone refresh response received: \(response)")
                        continuation.resume()
                    }
                },
                errorHandler: { [weak self] error in
                    Task { @MainActor in
                        self?.isRefreshing = false
                        logger.error("iPhone refresh failed: \(error.localizedDescription)")
                        continuation.resume()
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
            if let error = error {
                logger.error("Activation failed: \(error.localizedDescription)")
            } else {
                logger.info("Activated: \(activationState.rawValue)")
                self?.isReachable = session.isReachable

                // Check for any existing application context
                if let data = session.receivedApplicationContext["shiftData"] as? Data {
                    self?.processReceivedData(data)
                }
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            guard let data = applicationContext["shiftData"] as? Data else {
                logger.warning("No shiftData in applicationContext")
                return
            }
            self?.processReceivedData(data)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isReachable = session.isReachable
            logger.info("Reachability changed: \(session.isReachable)")
        }
    }

    // MARK: - Private

    private func processReceivedData(_ data: Data) {
        do {
            let payload = try JSONDecoder().decode(WatchDataPayload.self, from: data)
            WatchDataStore.shared.update(from: payload)
            logger.info("Received data: user=\(payload.userShift != nil), friends=\(payload.friendShifts.count)")
        } catch {
            logger.error("Failed to decode payload: \(error.localizedDescription)")
        }
    }
}
