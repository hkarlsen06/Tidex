import Foundation

enum UserGeneratedContentFilter {
  private static let patterns: [String] = [
    #"kys"#,
    #"kill\s+yourself"#,
    #"rape"#,
    #"rapist"#,
    #"porn"#,
    #"pornography"#,
    #"nude\s+pics?"#,
    #"send\s+nudes?"#,
    #"nigger"#,
    #"nigga"#,
    #"faggot"#,
    #"tranny"#,
    #"retard"#,
    #"heil\s+hitler"#,
    #"gas\s+the\s+jews"#,
  ]

  private static let regularExpressions: [NSRegularExpression] = patterns.compactMap {
    try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
  }

  static func containsBlockedText(_ text: String) -> Bool {
    let normalizedText = text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(
        of: #"[^A-Za-z0-9]+"#,
        with: " ",
        options: .regularExpression
      )

    let range = NSRange(normalizedText.startIndex..<normalizedText.endIndex, in: normalizedText)
    return regularExpressions.contains { expression in
      expression.firstMatch(in: normalizedText, range: range) != nil
    }
  }
}
