import Foundation

enum WageyDeeplinkTextSegment: Equatable {
  case text(String)
  case deeplink(title: String, url: URL)
}

enum WageyDeeplinkTextSplitter {
  private static let markdownLinkPattern = #"\[([^\]]+)\]\(([^)\s]+)\)"#

  static func containsDeeplink(in text: String) -> Bool {
    split(text).contains { segment in
      if case .deeplink = segment {
        return true
      }
      return false
    }
  }

  static func split(_ text: String) -> [WageyDeeplinkTextSegment] {
    guard let regex = try? NSRegularExpression(pattern: markdownLinkPattern) else {
      return [.text(text)]
    }

    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    let matches = regex.matches(in: text, range: fullRange)
    guard !matches.isEmpty else {
      return [.text(text)]
    }

    var segments: [WageyDeeplinkTextSegment] = []
    var currentLocation = 0

    for match in matches {
      guard match.numberOfRanges == 3 else { continue }

      let title = nsText.substring(with: match.range(at: 1))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let rawURL = nsText.substring(with: match.range(at: 2))
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
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
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
