import Foundation

extension String {
  /// Uppercase only the first character using the provided locale.
  /// Unlike `.capitalized`, this preserves casing for subsequent words (e.g. "I morgen").
  func sentenceCased(locale: Locale = .appLocale) -> String {
    guard !isEmpty else { return self }
    return prefix(1).uppercased(with: locale) + dropFirst()
  }

  /// Heuristic: true if the string contains any RTL script characters.
  var isRightToLeft: Bool {
    for scalar in unicodeScalars {
      let value = scalar.value
      if Self.rtlScalarRanges.contains(where: { $0.contains(value) }) {
        return true
      }
    }
    return false
  }

  private static let rtlScalarRanges: [ClosedRange<UInt32>] = [
    0x0590...0x05FF,  // Hebrew
    0x0600...0x06FF,  // Arabic
    0x0700...0x074F,  // Syriac
    0x0750...0x077F,  // Arabic Supplement
    0x0780...0x07BF,  // Thaana
    0x07C0...0x07FF,  // NKo
    0x0800...0x083F,  // Samaritan
    0x0840...0x085F,  // Mandaic
    0x0860...0x086F,  // Syriac Supplement
    0x08A0...0x08FF,  // Arabic Extended-A
    0xFB1D...0xFB4F,  // Hebrew presentation forms
    0xFB50...0xFDFF,  // Arabic presentation forms-A
    0xFE70...0xFEFF,  // Arabic presentation forms-B
    0x1EE00...0x1EEFF,  // Arabic mathematical symbols
  ]
}
