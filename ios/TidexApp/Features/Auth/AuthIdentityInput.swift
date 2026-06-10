import Foundation

internal enum AuthIdentityInputType: Equatable {
  case email
  case phone
  case unknown
}

internal enum AuthIdentityInput {
  private static let phoneCharacters: CharacterSet = CharacterSet(charactersIn: "+0123456789 -")
  private static let norwegianPhoneDigitCount: Int = 8
  private static let internationalPrefixLength: Int = 2

  internal static func detectType(_ value: String) -> AuthIdentityInputType {
    let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.contains("@"), trimmed.contains(".") {
      return .email
    }

    if trimmed.hasPrefix("+")
      || trimmed.allSatisfy({ String($0).rangeOfCharacter(from: phoneCharacters) != nil })
    {
      let digits: String = trimmed.filter(\.isNumber)
      if digits.count >= norwegianPhoneDigitCount {
        return .phone
      }
    }

    return .unknown
  }

  internal static func normalizedPhone(
    _ value: String,
    defaultCountryCode: String = "+47"
  ) -> String {
    let cleaned: String = value.filter { $0.isNumber || $0 == "+" }

    if cleaned.hasPrefix("+") {
      return cleaned
    }

    if cleaned.hasPrefix("00") {
      return "+" + cleaned.dropFirst(internationalPrefixLength)
    }

    if cleaned.count == norwegianPhoneDigitCount {
      return defaultCountryCode + cleaned
    }

    return cleaned
  }
}
