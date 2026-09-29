import Foundation

internal enum FriendsComposerAttachmentLimits {
  internal static let maxImagesPerMessage: Int = 4
}

internal enum FriendsComposerAttachmentDraft: Codable, Equatable {
  case image(ImageAttachment)
  case shiftSnapshot(ComposerShiftSnapshotDraft)

  private enum CodingKeys: String, CodingKey {
    case type
    case image
    case shiftSnapshot = "shift_snapshot"
  }

  private enum DraftType: String, Codable {
    case image
    case shiftSnapshot = "shift_snapshot"
  }

  internal init(from decoder: Decoder) throws {
    let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(
      keyedBy: CodingKeys.self)
    let type: DraftType = try container.decode(DraftType.self, forKey: .type)

    switch type {
    case .image:
      self = .image(try container.decode(ImageAttachment.self, forKey: .image))

    case .shiftSnapshot:
      self = .shiftSnapshot(
        try container.decode(ComposerShiftSnapshotDraft.self, forKey: .shiftSnapshot)
      )
    }
  }

  internal func encode(to encoder: Encoder) throws {
    var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .image(let image):
      try container.encode(DraftType.image, forKey: .type)
      try container.encode(image, forKey: .image)

    case .shiftSnapshot(let draft):
      try container.encode(DraftType.shiftSnapshot, forKey: .type)
      try container.encode(draft, forKey: .shiftSnapshot)
    }
  }

  internal var imageAttachment: ImageAttachment? {
    guard case .image(let image) = self else {
      return nil
    }
    return image
  }

  internal var shiftSnapshotDraft: ComposerShiftSnapshotDraft? {
    guard case .shiftSnapshot(let draft) = self else {
      return nil
    }
    return draft
  }

  internal var shiftSnapshot: FriendShiftSnapshot? {
    shiftSnapshotDraft?.snapshot
  }

  internal var previewKind: FriendLastMessagePreviewKind {
    switch self {
    case .image:
      return .image

    case .shiftSnapshot:
      return .shiftSnapshot
    }
  }

  internal var metadataData: Data? {
    guard let shiftSnapshot else {
      return nil
    }
    return try? JSONEncoder().encode(
      FriendRichContentEnvelope(
        content: FriendRichContentEnvelope.Content(
          kind: FriendLastMessagePreviewKind.shiftSnapshot.rawValue,
          shiftSnapshot: shiftSnapshot.normalizedForTransport
        )
      )
    )
  }
}

extension Array where Element == FriendsComposerAttachmentDraft {
  internal var imageAttachments: [ImageAttachment] {
    compactMap(\.imageAttachment)
  }

  internal var shiftSnapshotDraft: ComposerShiftSnapshotDraft? {
    compactMap(\.shiftSnapshotDraft).first
  }

  internal var shiftSnapshot: FriendShiftSnapshot? {
    shiftSnapshotDraft?.snapshot
  }

  internal var hasImageAttachments: Bool {
    contains { $0.imageAttachment != nil }
  }

  internal var hasShiftSnapshot: Bool {
    contains { $0.shiftSnapshot != nil }
  }

  internal var metadataData: Data? {
    compactMap(\.metadataData).first
  }
}
