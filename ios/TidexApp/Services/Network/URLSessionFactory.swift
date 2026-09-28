import Foundation

/// Factory for shared URLSession instances with different timeout configurations.
/// Consolidates URLSession creation to avoid multiple connection pools, which:
/// - Reduces resource usage and memory consumption
/// - Provides consistent timeout handling across the app
/// - Allows URLSession to optimize connection reuse
enum URLSessionFactory {
  /// Standard session for most API calls (30s request, 60s resource timeout)
  /// Use for: SharingService, general API calls
  static let standard: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    return URLSession(configuration: config)
  }()

  /// Quick session for lightweight, time-sensitive calls (15s request, 30s resource timeout)
  /// Use for: ScreenshotNotificationService, quick status checks
  static let quick: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
  }()

  /// Long-running session for heavy operations (60s request, 120s resource timeout)
  /// Use for: DataSettingsViewModel (export/import), large data transfers
  static let longRunning: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 120
    return URLSession(configuration: config)
  }()
}
