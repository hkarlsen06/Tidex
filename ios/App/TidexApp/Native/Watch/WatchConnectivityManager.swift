import Foundation
import WatchConnectivity
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WatchConnectivityManager")

/// Manages Watch Connectivity for the iOS app
/// Sends shift data to the paired Apple Watch via applicationContext
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published private(set) var isWatchPaired = false
    @Published private(set) var isWatchAppInstalled = false

    private override init() {
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
        guard WCSession.isSupported() else {
            return
        }

        let session = WCSession.default

        guard session.activationState == .activated else {
            logger.info("WCSession not activated - skipping Watch update")
            return
        }

        guard session.isPaired else {
            logger.info("No paired Watch - skipping update")
            return
        }

        guard session.isWatchAppInstalled else {
            logger.info("Watch app not installed - skipping update")
            return
        }

        // Build and send payload in background
        Task {
            do {
                let payload = await WatchDataConverter.buildPayload(for: userId)
                let data = try JSONEncoder().encode(payload)
                let context: [String: Any] = ["shiftData": data]
                try session.updateApplicationContext(context)
                logger.info("Sent Watch update: user=\(payload.userShift != nil), friends=\(payload.friendShifts.count)")
            } catch {
                logger.error("Failed to send Watch update: \(error.localizedDescription)")
            }
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
        Task { @MainActor in
            if let error = error {
                logger.error("WCSession activation failed: \(error.localizedDescription)")
            } else {
                logger.info("WCSession activated: \(activationState.rawValue)")
                self.updatePairingState(session)
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
        Task { @MainActor in
            self.updatePairingState(session)
        }
    }

    /// Handle refresh request from Watch
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            if message["action"] as? String == "refresh" {
                logger.info("Watch requested refresh")

                guard let userId = AppCoordinator.shared.userId else {
                    replyHandler(["error": "Not authenticated"])
                    return
                }

                // Trigger sync for user shifts
                _ = await SyncCoordinator.shared.sync(reason: .watchRefresh, userId: userId)

                // Also fetch friend data so it's available for the Watch
                await self.refreshFriendData(userId: userId)

                // Send updated data to Watch
                self.sendUpdatedData(userId: userId)
                replyHandler(["success": true])
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

            logger.info("Watch refresh: fetched \(sharers.count) sharers, \(previews.count) shift previews")
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
}
