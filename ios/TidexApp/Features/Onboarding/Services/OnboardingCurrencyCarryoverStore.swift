import Foundation

/// Stores the preferred pre-auth onboarding currency for post-auth bootstrap.
enum OnboardingCurrencyCarryoverStore {
  private static let key = "preAuthPreferredCurrency"

  static func readValidPreferredCurrency() -> String? {
    guard let symbol = UserDefaults.standard.string(forKey: key) else {
      return nil
    }

    guard OnboardingCurrencyResolver.isSupportedCurrency(symbol) else {
      UserDefaults.standard.removeObject(forKey: key)
      return nil
    }

    return symbol
  }

  static func writePreferredCurrency(_ symbol: String) {
    guard OnboardingCurrencyResolver.isSupportedCurrency(symbol) else { return }
    UserDefaults.standard.set(symbol, forKey: key)
  }

  static func clearPreferredCurrency() {
    UserDefaults.standard.removeObject(forKey: key)
  }
}
