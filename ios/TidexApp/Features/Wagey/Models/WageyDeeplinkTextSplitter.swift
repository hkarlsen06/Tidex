import Foundation

enum WageyDeeplinkTextSegment: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case text(String)  // swiftlint:disable:this sorted_enum_cases
  case deeplink(title: String, url: URL)  // swiftlint:disable:this sorted_enum_cases
}

enum WageyDeeplinkTextSplitter {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  private static let markdownLinkPattern = #"\[([^\]]+)\]\(([^)\s]+)\)"#  // swiftlint:disable:this explicit_type_interface line_length

  static func containsDeeplink(in text: String) -> Bool {  // swiftlint:disable:this explicit_acl
    split(text).contains { segment in
      if case .deeplink = segment {
        return true
      }
      return false
    }
  }

  static func split(_ text: String) -> [WageyDeeplinkTextSegment] {  // swiftlint:disable:this explicit_acl
    guard let regex = try? NSRegularExpression(pattern: markdownLinkPattern) else {
      return [.text(text)]
    }

    let nsText = text as NSString  // swiftlint:disable:this explicit_type_interface legacy_objc_type
    let fullRange = NSRange(location: 0, length: nsText.length)  // swiftlint:disable:this explicit_type_interface
    let matches = regex.matches(in: text, range: fullRange)  // swiftlint:disable:this explicit_type_interface
    guard !matches.isEmpty else {
      return [.text(text)]
    }

    var segments: [WageyDeeplinkTextSegment] = []
    var currentLocation = 0  // swiftlint:disable:this explicit_type_interface

    for match in matches {
      guard match.numberOfRanges == 3 else { continue }  // swiftlint:disable:this no_magic_numbers

      let title = nsText.substring(with: match.range(at: 1))  // swiftlint:disable:this explicit_type_interface
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let rawURL = nsText.substring(with: match.range(at: 2))  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard let url = URL(string: rawURL), isTidexDeeplink(url), !title.isEmpty else {
        continue
      }

      appendText(
        nsText.substring(
          with: NSRange(location: currentLocation, length: match.range.location - currentLocation)
        ),
        to: &segments
      )
      segments.append(.deeplink(title: title, url: url))
      currentLocation = match.range.location + match.range.length
    }

    appendText(
      nsText.substring(
        with: NSRange(location: currentLocation, length: nsText.length - currentLocation)
      ),
      to: &segments
    )

    return segments.isEmpty ? [.text(text)] : segments
  }

  private static func appendText(_ text: String, to segments: inout [WageyDeeplinkTextSegment]) {
    let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline
    segments.append(.text(trimmed))
  }

  private static func isTidexDeeplink(_ url: URL) -> Bool {
    if url.scheme?.lowercased() == "tidex" {
      return true
    }

    guard
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http"
    else {
      return false
    }

    return url.host?.lowercased() == "app.tidex.no"
  }
}
