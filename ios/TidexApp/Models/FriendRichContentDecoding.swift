import Foundation

internal struct FriendRichContentEnvelope: Codable {
  internal struct Content: Codable {
    internal let kind: String?
    internal let shiftSnapshot: FriendShiftSnapshot?

    internal enum CodingKeys: String, CodingKey {
      case kind
      case shiftSnapshot = "shift_snapshot"
    }
  }

  internal let content: Content?
}

internal enum FriendRichContentDecoder {
  internal static func richContentKind(from metadataData: Data?) -> FriendRichContentKind? {
    guard
      let envelope = decodeEnvelope(from: metadataData),
      let rawKind = envelope.content?.kind?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawKind.isEmpty
    else {
      return nil
    }

    switch rawKind {
    case FriendLastMessagePreviewKind.shiftSnapshot.rawValue:
      guard let snapshot = envelope.content?.shiftSnapshot, snapshot.isSupportedSchemaVersion else {
        return .unsupported(rawKind)
      }
      return .shiftSnapshot

    default:
      return .unsupported(rawKind)
    }
  }

  internal static func richContent(from metadataData: Data?) -> FriendRichContent? {
    guard let envelope = decodeEnvelope(from: metadataData) else {
      return nil
    }
    guard let snapshot = envelope.content?.shiftSnapshot, snapshot.isSupportedSchemaVersion else {
      return nil
    }

    guard envelope.content?.kind == FriendLastMessagePreviewKind.shiftSnapshot.rawValue else {
      return nil
    }

    return .shiftSnapshot(snapshot)
  }

  private static func decodeEnvelope(from metadataData: Data?) -> FriendRichContentEnvelope? {
    guard let metadataData, !metadataData.isEmpty else {
      return nil
    }
    return try? JSONDecoder().decode(FriendRichContentEnvelope.self, from: metadataData)
  }
}

internal enum FriendMessagePreviewPolicy {
  internal static func resolvedPreviewKind(
    explicitPreviewKind: FriendLastMessagePreviewKind? = nil,
    body: String?,
    richContentKind: FriendRichContentKind? = nil,
    hasImageAttachment: Bool
  ) -> FriendLastMessagePreviewKind {
    if let explicitPreviewKind {
      return explicitPreviewKind
    }

    if normalizedBody(body) != nil {
      return .text
    }

    if hasImageAttachment {
      return .image
    }

    switch richContentKind {
    case .shiftSnapshot:
      return .shiftSnapshot

    case .unsupported:
      return .unknown

    case nil:
      return .unknown
    }
  }

  internal static func previewText(
    body: String?,
    previewKind: FriendLastMessagePreviewKind
  ) -> String? {
    if let normalizedBody = normalizedBody(body), previewKind == .text {
      return normalizedBody
    }

    switch previewKind {
    case .text:
      return String(localized: .friendsChatPreviewUnsupported)

    case .image:
      return String(localized: .friendsChatPreviewImage)

    case .shiftSnapshot:
      return String(localized: .friendsChatPreviewSharedShift)

    case .unknown:
      return String(localized: .friendsChatPreviewUnsupported)
    }
  }

  private static func normalizedBody(_ body: String?) -> String? {
    let snippet: String? = body?
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let snippet, !snippet.isEmpty else {
      return nil
    }
    return snippet
  }
}
