// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable anonymous_argument_in_multiline_closure explicit_acl explicit_top_level_acl explicit_type_interface
import Foundation

enum UserGeneratedContentFilter {
  private static let patterns: [String] = [
    #"kys"#,
    #"kill\s+yourself"#,
    #"suicide"#,
    #"selvmord"#,
    #"ta\s+livet\s+ditt"#,
    #"drep\s+deg\s+selv"#,
    #"rape"#,
    #"rapist"#,
    #"voldtekt"#,
    #"voldtektsmann"#,
    #"porn"#,
    #"pornography"#,
    #"porno"#,
    #"pedophile"#,
    #"pedofil"#,
    #"pedo"#,
    #"nude\s+pics?"#,
    #"send\s+nudes?"#,
    #"send\s+nakenbilder"#,
    #"nakenbilder"#,
    #"nigger"#,
    #"nigga"#,
    #"faggot"#,
    #"homo"#,
    #"tranny"#,
    #"retard"#,
    #"tilbakestaende"#,
    #"heil\s+hitler"#,
    #"nazi"#,
    #"nazist"#,
    #"gas\s+the\s+jews"#,
    #"gass\s+jodene"#,
    #"jodeutryddelse"#,
    #"neger"#,
    #"svarting"#,
    #"pakkis"#,
    #"jaevla\s+utlending"#,
    #"hore"#,
    #"fitte"#,
    #"kuk"#,
  ]

  private static let regularExpressions: [NSRegularExpression] = patterns.compactMap {
    try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
  }

  static func containsBlockedText(_ text: String) -> Bool {
    let normalizedText =
      text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(of: "æ", with: "ae")
      .replacingOccurrences(of: "ø", with: "o")
      .replacingOccurrences(of: "å", with: "a")
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
