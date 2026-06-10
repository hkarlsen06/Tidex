import Foundation

/// Stores the preferred pre-auth onboarding currency for post-auth bootstrap.
internal enum OnboardingCurrencyCarryoverStore {
  private static let key: String = "preAuthPreferredCurrency"

  internal static func readValidPreferredCurrency() -> String? {
    guard let symbol = UserDefaults.standard.string(forKey: key) else {
      return nil
    }

    guard OnboardingCurrencyResolver.isSupportedCurrency(symbol) else {
      UserDefaults.standard.removeObject(forKey: key)
      return nil
    }

    return symbol
  }

  internal static func writePreferredCurrency(_ symbol: String) {
    guard OnboardingCurrencyResolver.isSupportedCurrency(symbol) else {
      return
    }
    UserDefaults.standard.set(symbol, forKey: key)
  }

  internal static func clearPreferredCurrency() {
    UserDefaults.standard.removeObject(forKey: key)
  }
}
