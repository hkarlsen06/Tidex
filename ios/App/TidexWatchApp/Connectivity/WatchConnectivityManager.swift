import Foundation
import WatchConnectivity
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WatchConnectivity")

/// Manages Watch Connectivity for the watchOS app
/// Receives shift data from the paired iPhone via applicationContext
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

    /// Request fresh data from iPhone
    /// Only works when iPhone is reachable
    func requestRefresh() {
        guard WCSession.default.isReachable else {
            logger.info("iPhone not reachable - cannot refresh")
            return
        }

        guard !isRefreshing else {
            logger.info("Refresh already in progress")
            return
        }

        isRefreshing = true

        WCSession.default.sendMessage(
            ["action": "refresh"],
            replyHandler: { [weak self] response in
                Task { @MainActor in
                    self?.isRefreshing = false
                    logger.info("Refresh response received: \(response)")
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.isRefreshing = false
                    logger.error("Refresh failed: \(error.localizedDescription)")
                }
            }
        )
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
