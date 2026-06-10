import Foundation

enum AuthIdentityInputType: Equatable {
  case email
  case phone
  case unknown
}

enum AuthIdentityInput {
  private static let phoneCharacters = CharacterSet(charactersIn: "+0123456789 -")

  static func detectType(_ value: String) -> AuthIdentityInputType {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.contains("@"), trimmed.contains(".") {
      return .email
    }

    if trimmed.hasPrefix("+")
      || trimmed.allSatisfy({ String($0).rangeOfCharacter(from: phoneCharacters) != nil })
    {
      let digits = trimmed.filter(\.isNumber)
      if digits.count >= 8 {
        return .phone
      }
    }

    return .unknown
  }

  static func normalizedPhone(
    _ value: String,
    defaultCountryCode: String = "+47"
  ) -> String {
    let cleaned = value.filter { $0.isNumber || $0 == "+" }

    if cleaned.hasPrefix("+") {
      return cleaned
    }

    if cleaned.hasPrefix("00") {
      return "+" + cleaned.dropFirst(2)
    }

    if cleaned.count == 8 {
      return defaultCountryCode + cleaned
    }

    return cleaned
  }
}
