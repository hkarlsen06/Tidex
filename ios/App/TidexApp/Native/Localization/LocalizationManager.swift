import Foundation
import SwiftUI

/// Manages locale detection for the native iOS app
/// Locale is determined solely by iOS Settings (Settings > Tidex > Language)
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
    }

    // MARK: - Published State

    @Published private(set) var currentLocale: AppLocale

    // MARK: - Initialization

    private init() {
        // Use iOS Settings app language preference (Settings > Tidex > Language)
        // This respects the per-app language setting in iOS
        currentLocale = Self.detectDeviceLocale()
    }

    // MARK: - Locale Detection

    /// Detect the device's preferred locale from iOS Settings
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

    // MARK: - Locale Refresh

    /// Refresh locale from iOS Settings
    /// Call this when the app returns to foreground in case user changed language in Settings
    func refreshLocale() {
        let newLocale = Self.detectDeviceLocale()
        if newLocale != currentLocale {
            currentLocale = newLocale

            // Also update App Group storage for widget compatibility
            if let sharedDefaults = UserDefaults(suiteName: APIConfiguration.appGroupID) {
                sharedDefaults.set(newLocale.rawValue, forKey: APIConfiguration.localeKey)
            }
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
