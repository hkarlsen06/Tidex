import ExyteChat
import ImageIO
import SwiftUI
import UIKit

struct FriendsChatDetectedLink: Equatable {
  let range: NSRange
  let text: String
  let url: URL
}

enum FriendsChatMessageLinkifier {
  private static let detector: NSDataDetector? = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue
  )
  private static let tidexSchemePattern: String = #"(?i)\btidex://[^\s<>()\[\]{}"']+"#
  private static let bareDomainPattern: String =
    #"(?i)(?<![@\w.-])(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}(?:/[^\s<>()\[\]{}"']*)?"#
  private static let trailingURLCharacters: Set<Character> = [
    ".", ",", "!", "?", ";", ":", ")", "]", "}",
  ]

  static func attributedString(
    for text: String,
    foregroundColor: Color,
    linkColor: Color
  ) -> AttributedString {
    var result = AttributedString(text)
    result.foregroundColor = foregroundColor

    for link in links(in: text) {
      guard
        let stringRange = Range(link.range, in: text),
        let lowerBound = AttributedString.Index(stringRange.lowerBound, within: result),
        let upperBound = AttributedString.Index(stringRange.upperBound, within: result)
      else {
        continue
      }

      let attributedRange = lowerBound..<upperBound
      result[attributedRange].link = link.url
      result[attributedRange].foregroundColor = linkColor
      result[attributedRange].underlineStyle = .single
    }

    return result
  }

  static func links(in text: String) -> [FriendsChatDetectedLink] {
    guard !text.isEmpty else {
      return []
    }

    var links: [FriendsChatDetectedLink] = []
    links.append(contentsOf: detectedURLLinks(in: text))
    links.append(contentsOf: regexLinks(in: text, pattern: tidexSchemePattern))
    links.append(contentsOf: regexLinks(in: text, pattern: bareDomainPattern))

    return nonOverlappingLinks(links)
  }

  private static func detectedURLLinks(in text: String) -> [FriendsChatDetectedLink] {
    guard let detector else {
      return []
    }

    let nsRange: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return detector.matches(in: text, options: [], range: nsRange).compactMap { match in
      guard let matchRange = trimmedRange(match.range, in: text) else {
        return nil
      }
      let displayText: String = substring(in: matchRange, text: text)
      guard let url = normalizedURL(for: displayText, detectedURL: match.url) else {
        return nil
      }
      return FriendsChatDetectedLink(range: matchRange, text: displayText, url: url)
    }
  }

  private static func regexLinks(in text: String, pattern: String) -> [FriendsChatDetectedLink] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }

    let nsRange: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: nsRange).compactMap { match in
      guard let matchRange = trimmedRange(match.range, in: text) else {
        return nil
      }
      let displayText: String = substring(in: matchRange, text: text)
      guard let url = normalizedURL(for: displayText, detectedURL: nil) else {
        return nil
      }
      return FriendsChatDetectedLink(range: matchRange, text: displayText, url: url)
    }
  }

  private static func nonOverlappingLinks(_ links: [FriendsChatDetectedLink])
    -> [FriendsChatDetectedLink]
  {
    links
      .sorted { lhs, rhs in
        if lhs.range.location == rhs.range.location {
          return lhs.range.length > rhs.range.length
        }
        return lhs.range.location < rhs.range.location
      }
      .reduce(into: [FriendsChatDetectedLink]()) { result, link in
        guard !result.contains(where: { NSIntersectionRange($0.range, link.range).length > 0 })
        else {
          return
        }
        result.append(link)
      }
  }

  private static func normalizedURL(for text: String, detectedURL: URL?) -> URL? {
    if hasURLScheme(text) {
      return URL(string: text) ?? detectedURL
    }

    if let detectedURL, hasURLScheme(detectedURL.absoluteString) {
      return detectedURL.scheme?.lowercased() == "http"
        ? URL(string: "https://\(text)") ?? detectedURL
        : detectedURL
    }

    return URL(string: "https://\(text)")
  }

  private static func hasURLScheme(_ text: String) -> Bool {
    text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
  }

  private static func trimmedRange(_ nsRange: NSRange, in text: String) -> NSRange? {
    guard var range = Range(nsRange, in: text) else {
      return nil
    }

    while range.lowerBound < range.upperBound,
      let last = text[range].last,
      trailingURLCharacters.contains(last)
    {
      range = range.lowerBound..<text.index(before: range.upperBound)
    }

    guard range.lowerBound < range.upperBound else {
      return nil
    }
    return NSRange(range, in: text)
  }

  private static func substring(in nsRange: NSRange, text: String) -> String {
    guard let range = Range(nsRange, in: text) else {
      return ""
    }
    return String(text[range])
  }
}

struct FriendsChatLinkedMessageText: View {
  let text: String
  let isCurrentUser: Bool

  var body: some View {
    Text(
      FriendsChatMessageLinkifier.attributedString(
        for: text,
        foregroundColor: foregroundColor,
        linkColor: linkColor
      )
    )
    .font(.tidexBody)
    .multilineTextAlignment(.leading)
    .fixedSize(horizontal: false, vertical: true)
    .environment(
      \.openURL,
      OpenURLAction { url in
        if AppDeepLinkResolver.resolve(url) != nil {
          AppCoordinator.shared.handleDeepLink(url)
          return .handled
        }

        return .systemAction(url)
      }
    )
  }

  private var foregroundColor: Color {
    isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary
  }

  private var linkColor: Color {
    isCurrentUser ? .tidexTextOnBrand : .tidexBlueText
  }
}