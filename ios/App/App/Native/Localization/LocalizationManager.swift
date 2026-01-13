import Foundation
import SwiftUI

/// Manages locale detection and switching for the native iOS app
/// Mirrors the behavior of LocaleAwareBridgeViewController.detectDeviceLocale()
@MainActor
final class LocalizationManager: ObservableObject, @unchecked Sendable {
    // Static shared instance created eagerly to avoid MainActor isolation issues
    static let shared: LocalizationManager = {
        // This runs on MainActor due to the class annotation
        LocalizationManager()
    }()

    // MARK: - Types

    enum AppLocale: String, CaseIterable {
        case norwegian = "no"
        case english = "en"

        var localeIdentifier: String {
            switch self {
            case .norwegian: return "nb_NO"
            case .english: return "en_US"
            }
        }

        var displayName: String {
            switch self {
            case .norwegian: return "Norsk"
            case .english: return "English"
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var currentLocale: AppLocale

    // MARK: - Initialization

    private init() {
        // Check for stored preference first
        if let storedLocale = UserDefaults.standard.string(forKey: APIConfiguration.localeKey),
           let locale = AppLocale(rawValue: storedLocale) {
            currentLocale = locale
        } else {
            // Fall back to device locale detection
            currentLocale = Self.detectDeviceLocale()
        }
    }

    // MARK: - Locale Detection

    /// Detect the device's preferred locale
    /// Mirrors the logic from LocaleAwareBridgeViewController
    static func detectDeviceLocale() -> AppLocale {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"

        // Check for Norwegian variants
        if preferredLanguage.hasPrefix("nb") ||
           preferredLanguage.hasPrefix("nn") ||
           preferredLanguage.hasPrefix("no") {
            return .norwegian
        }

        return .english
    }

    // MARK: - Locale Switching

    /// Set the current locale and persist it
    func setLocale(_ locale: AppLocale) {
        currentLocale = locale
        UserDefaults.standard.set(locale.rawValue, forKey: APIConfiguration.localeKey)

        // Also update App Group storage for widget compatibility
        if let sharedDefaults = UserDefaults(suiteName: APIConfiguration.appGroupID) {
            sharedDefaults.set(locale.rawValue, forKey: APIConfiguration.localeKey)
        }
    }

    // MARK: - String Access

    /// Get a localized string for the current locale
    func string(_ key: String) -> String {
        return AuthStrings.string(key, locale: currentLocale)
    }

    /// Get a localized string with format arguments
    func string(_ key: String, _ args: CVarArg...) -> String {
        let format = AuthStrings.string(key, locale: currentLocale)
        return String(format: format, arguments: args)
    }
}

// MARK: - Environment Key

private struct LocalizationManagerKey: EnvironmentKey {
    static let defaultValue: LocalizationManager = MainActor.assumeIsolated {
        LocalizationManager.shared
    }
}

extension EnvironmentValues {
    var localization: LocalizationManager {
        get { self[LocalizationManagerKey.self] }
        set { self[LocalizationManagerKey.self] = newValue }
    }
}
