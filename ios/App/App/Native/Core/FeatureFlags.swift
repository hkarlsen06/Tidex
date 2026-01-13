import Foundation
import SwiftUI

/// Feature flags for controlling native vs WebView routing
/// These flags allow gradual migration from WebView to native screens
enum FeatureFlags {

    // MARK: - Storage Keys

    private static let prefix = "tidex.feature."

    enum Key: String {
        case useNativeAuth = "useNativeAuth"
        case useNativeDashboard = "useNativeDashboard"
        case useNativeShifts = "useNativeShifts"
        case useNativeSettings = "useNativeSettings"

        var storageKey: String {
            return FeatureFlags.prefix + rawValue
        }
    }

    // MARK: - Default Values

    /// Default feature flag values
    /// These can be overridden by remote config in the future
    private static let defaults: [Key: Bool] = [
        .useNativeAuth: true,        // Enable native auth screens by default
        .useNativeDashboard: false,  // Keep WebView dashboard for now
        .useNativeShifts: false,     // Keep WebView shifts for now
        .useNativeSettings: false    // Keep WebView settings for now
    ]

    // MARK: - Flag Access

    /// Check if a feature flag is enabled
    static func isEnabled(_ key: Key) -> Bool {
        // Check UserDefaults first (allows local override)
        if UserDefaults.standard.object(forKey: key.storageKey) != nil {
            return UserDefaults.standard.bool(forKey: key.storageKey)
        }

        // Fall back to default value
        return defaults[key] ?? false
    }

    /// Set a feature flag value (for debugging/testing)
    static func setEnabled(_ key: Key, value: Bool) {
        UserDefaults.standard.set(value, forKey: key.storageKey)
    }

    /// Reset a feature flag to its default value
    static func reset(_ key: Key) {
        UserDefaults.standard.removeObject(forKey: key.storageKey)
    }

    /// Reset all feature flags to defaults
    static func resetAll() {
        for key in Key.allCases {
            reset(key)
        }
    }
}

// MARK: - CaseIterable Conformance

extension FeatureFlags.Key: CaseIterable {}
