import Foundation

// MARK: - MFA Factor Model

extension SecuritySettingsViewModel {
  struct MFAFactor: Identifiable {
    let id: String
    let friendlyName: String?
    let createdAt: Date

    var displayName: String {
      friendlyName ?? "Authenticator"
    }

    var formattedDate: String {
      createdAt.formatted(
        Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.appLocale).calendar(.gregorian)
      )
    }
  }
}
