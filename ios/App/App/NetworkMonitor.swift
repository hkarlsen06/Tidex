import Foundation
import Network

/// Protocol for receiving network connectivity status changes
protocol NetworkMonitorDelegate: AnyObject {
    func networkStatusDidChange(isConnected: Bool)
}

/// Centralized network connectivity monitoring using NWPathMonitor.
/// Provides reliable iOS-native network state detection.
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "no.tidex.app.NetworkMonitor", qos: .utility)

    weak var delegate: NetworkMonitorDelegate?

    /// Current network connectivity state
    private(set) var isConnected: Bool = true

    /// Whether monitoring has been started
    private var isMonitoring = false

    /// Debounce timer to prevent rapid state changes
    private var debounceWorkItem: DispatchWorkItem?

    /// Debounce delay in seconds
    private let debounceDelay: TimeInterval = 0.5

    private init() {}

    /// Start monitoring network connectivity.
    /// Safe to call multiple times - will only start once.
    func startMonitoring() {
        guard !isMonitoring else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        monitor.start(queue: queue)
        isMonitoring = true

        print("[NetworkMonitor] Started monitoring")
    }

    /// Stop monitoring network connectivity.
    func stopMonitoring() {
        guard isMonitoring else { return }

        monitor.cancel()
        isMonitoring = false
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        print("[NetworkMonitor] Stopped monitoring")
    }

    /// Handle network path updates with debouncing
    private func handlePathUpdate(_ path: NWPath) {
        let newConnected = path.status == .satisfied

        // Cancel any pending debounce
        debounceWorkItem?.cancel()

        // Create new debounced update
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Only notify if state actually changed
            if self.isConnected != newConnected {
                self.isConnected = newConnected

                print("[NetworkMonitor] Connection state changed: \(newConnected ? "connected" : "disconnected")")

                // Notify delegate on main queue
                DispatchQueue.main.async {
                    self.delegate?.networkStatusDidChange(isConnected: newConnected)
                }
            }
        }

        debounceWorkItem = workItem

        // Execute after debounce delay
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }
}
