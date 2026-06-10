import Foundation
import os.log
import SwiftData

private let composerDraftLogger = Logger(
  subsystem: "com.tidex.app",
  category: "FriendsComposerDraftStore"
)

@MainActor
final class FriendsComposerDraftStore {
  private enum Storage {
    static let appGroupId = "group.no.tidex.app"
    static let directoryName = "FriendsComposerDraftAttachments"
  }

  private struct PersistedImageAttachmentDraft: Codable {
    let id: String
    let mediaType: String
    let relativePath: String
  }

  private enum PersistedAttachmentDraft: Codable {
    case image(PersistedImageAttachmentDraft)
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

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let type = try container.decode(DraftType.self, forKey: .type)

      switch type {
      case .image:
        self = .image(try container.decode(PersistedImageAttachmentDraft.self, forKey: .image))

      case .shiftSnapshot:
        self = .shiftSnapshot(
          try container.decode(ComposerShiftSnapshotDraft.self, forKey: .shiftSnapshot)
        )
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)

      switch self {
      case .image(let imageDraft):
        try container.encode(DraftType.image, forKey: .type)
        try container.encode(imageDraft, forKey: .image)

      case .shiftSnapshot(let draft):
        try container.encode(DraftType.shiftSnapshot, forKey: .type)
        try container.encode(draft, forKey: .shiftSnapshot)
      }
    }
  }

  struct Draft: Equatable {
    let text: String
    let attachments: [FriendsComposerAttachmentDraft]

    var attachment: FriendsComposerAttachmentDraft? {
      attachments.first
    }
  }

  static let shared = FriendsComposerDraftStore()

  private enum Expiry {
    static let interval: TimeInterval = 60 * 60 * 24 * 7
  }

  private let container: ModelContainer
  private let storeActor: LocalStoreActor
  private let attachmentsDirectory: URL

  init(
    container: ModelContainer? = nil,
    storeActor: LocalStoreActor? = nil,
    attachmentsDirectory: URL? = nil
  ) {
    if let container, let storeActor {
      self.container = container
      self.storeActor = storeActor
    } else {
      self.container = LocalStore.shared.container
      self.storeActor = LocalStore.shared.storeActor
    }

    self.attachmentsDirectory = attachmentsDirectory ?? Self.defaultAttachmentsDirectory()
    ensureAttachmentsDirectoryExists()
  }

  func loadDraft(
    threadId: String,
    viewerUserId: String
  ) async -> Draft? {
    await clearExpiredDrafts()

    let context = ModelContext(container)
    let compositeKey = "\(viewerUserId):\(threadId)"
    let descriptor = FetchDescriptor<LocalPendingFriendComposerDraft>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )

    do {
      guard let localDraft = try context.fetch(descriptor).first else {
        return nil
      }
      let text = localDraft.draftText ?? ""
      var attachments: [FriendsComposerAttachmentDraft] = []

      if let attachmentData = localDraft.attachmentData {
        do {
          let decodedDrafts = try decodeStoredAttachmentDrafts(
            from: attachmentData,
            threadId: threadId,
            viewerUserId: viewerUserId
          )
          attachments = decodedDrafts.attachments

          if decodedDrafts.shouldMigrateLegacyInlineImages {
            await saveAttachmentDrafts(
              attachments,
              threadId: threadId,
              viewerUserId: viewerUserId
            )
          }
        } catch {
          composerDraftLogger.error(
            "Failed to decode pending composer attachment draft: \(error.localizedDescription)")
          await clearAttachmentDraft(threadId: threadId, viewerUserId: viewerUserId)
        }
      }

      let draft = Draft(
        text: text,
        attachments: attachments
      )

      guard !draft.text.isEmpty || !draft.attachments.isEmpty else {
        await clearDraft(threadId: threadId, viewerUserId: viewerUserId)
        return nil
      }

      return draft
    } catch {
      composerDraftLogger.error(
        "Failed to load pending composer draft: \(error.localizedDescription)")
      await clearDraft(threadId: threadId, viewerUserId: viewerUserId)
      return nil
    }
  }

  func loadDraftText(threadId: String, viewerUserId: String) async -> String {
    await loadDraft(threadId: threadId, viewerUserId: viewerUserId)?.text ?? ""
  }

  func loadAttachmentDraft(
    threadId: String,
    viewerUserId: String
  ) async -> FriendsComposerAttachmentDraft? {
    await loadDraft(threadId: threadId, viewerUserId: viewerUserId)?.attachment
  }

  func loadAttachmentDrafts(
    threadId: String,
    viewerUserId: String
  ) async -> [FriendsComposerAttachmentDraft] {
    await loadDraft(threadId: threadId, viewerUserId: viewerUserId)?.attachments ?? []
  }

  func saveDraftText(
    _ draftText: String,
    threadId: String,
    viewerUserId: String
  ) async {
    await clearExpiredDrafts()

    do {
      if draftText.isEmpty {
        try await storeActor.clearPendingFriendComposerDraftText(
          threadId: threadId,
          viewerUserId: viewerUserId
        )
      } else {
        try await storeActor.savePendingFriendComposerDraftText(
          draftText,
          threadId: threadId,
          viewerUserId: viewerUserId
        )
      }
    } catch {
      composerDraftLogger.error(
        "Failed to save pending composer text draft: \(error.localizedDescription)")
    }
  }

  func saveDraft(
    text: String,
    attachment: FriendsComposerAttachmentDraft?,
    threadId: String,
    viewerUserId: String
  ) async {
    await saveDraft(
      text: text,
      attachments: attachment.map { [$0] } ?? [],
      threadId: threadId,
      viewerUserId: viewerUserId
    )
  }

  func saveDraft(
    text: String,
    attachments: [FriendsComposerAttachmentDraft],
    threadId: String,
    viewerUserId: String
  ) async {
    await saveDraftText(text, threadId: threadId, viewerUserId: viewerUserId)

    if attachments.isEmpty {
      await clearAttachmentDraft(threadId: threadId, viewerUserId: viewerUserId)
    } else {
      await saveAttachmentDrafts(attachments, threadId: threadId, viewerUserId: viewerUserId)
    }
  }

  func saveAttachmentDraft(
    _ attachment: FriendsComposerAttachmentDraft,
    threadId: String,
    viewerUserId: String
  ) async {
    await saveAttachmentDrafts(
      [attachment],
      threadId: threadId,
      viewerUserId: viewerUserId
    )
  }

  func saveAttachmentDrafts(
    _ attachments: [FriendsComposerAttachmentDraft],
    threadId: String,
    viewerUserId: String
  ) async {
    await clearExpiredDrafts()

    do {
      if attachments.isEmpty {
        removeAttachmentFiles(threadId: threadId, viewerUserId: viewerUserId)
        try await storeActor.clearPendingFriendComposerDraftAttachmentData(
          threadId: threadId,
          viewerUserId: viewerUserId
        )
      } else {
        let attachmentData = try encodeStoredAttachmentDrafts(
          attachments,
          threadId: threadId,
          viewerUserId: viewerUserId
        )
        try await storeActor.savePendingFriendComposerDraftAttachmentData(
          attachmentData,
          threadId: threadId,
          viewerUserId: viewerUserId
        )
      }
    } catch {
      composerDraftLogger.error(
        "Failed to save pending composer draft: \(error.localizedDescription)")
    }
  }

  func clearAttachmentDraft(threadId: String, viewerUserId: String) async {
    do {
      removeAttachmentFiles(threadId: threadId, viewerUserId: viewerUserId)
      try await storeActor.clearPendingFriendComposerDraftAttachmentData(
        threadId: threadId,
        viewerUserId: viewerUserId
      )
    } catch {
      composerDraftLogger.error(
        "Failed to clear pending composer draft: \(error.localizedDescription)")
    }
  }

  func clearDraft(threadId: String, viewerUserId: String) async {
    do {
      removeAttachmentFiles(threadId: threadId, viewerUserId: viewerUserId)
      try await storeActor.clearPendingFriendComposerDraft(
        threadId: threadId,
        viewerUserId: viewerUserId
      )
    } catch {
      composerDraftLogger.error(
        "Failed to clear pending composer draft: \(error.localizedDescription)")
    }
  }

  func clearExpiredDrafts(referenceDate: Date = Date()) async {
    do {
      for expiredDraft in loadExpiredDraftRecords(
        olderThan: referenceDate.addingTimeInterval(-Expiry.interval))
      {
        removeAttachmentFiles(
          threadId: expiredDraft.threadId,
          viewerUserId: expiredDraft.viewerUserId
        )
      }

      try await storeActor.clearExpiredPendingFriendComposerDrafts(
        olderThan: referenceDate.addingTimeInterval(-Expiry.interval)
      )
    } catch {
      composerDraftLogger.error(
        "Failed to clear expired composer drafts: \(error.localizedDescription)")
    }
  }

  private struct DecodedAttachmentDrafts {
    let attachments: [FriendsComposerAttachmentDraft]
    let shouldMigrateLegacyInlineImages: Bool
  }

  private func decodeStoredAttachmentDrafts(
    from data: Data,
    threadId: String,
    viewerUserId: String
  ) throws -> DecodedAttachmentDrafts {
    let decoder = JSONDecoder()

    if let persistedDrafts = try? decoder.decode([PersistedAttachmentDraft].self, from: data) {
      return DecodedAttachmentDrafts(
        attachments: try materializePersistedAttachmentDrafts(
          persistedDrafts,
          threadId: threadId,
          viewerUserId: viewerUserId
        ),
        shouldMigrateLegacyInlineImages: false
      )
    }

    if let attachments = try? decoder.decode([FriendsComposerAttachmentDraft].self, from: data) {
      return DecodedAttachmentDrafts(
        attachments: attachments,
        shouldMigrateLegacyInlineImages: attachments.hasImageAttachments
      )
    }

    let legacyAttachment = try decoder.decode(FriendsComposerAttachmentDraft.self, from: data)
    return DecodedAttachmentDrafts(
      attachments: [legacyAttachment],
      shouldMigrateLegacyInlineImages: legacyAttachment.imageAttachment != nil
    )
  }

  private func encodeStoredAttachmentDrafts(
    _ attachments: [FriendsComposerAttachmentDraft],
    threadId: String,
    viewerUserId: String
  ) throws -> Data {
    let persistedDrafts = try attachments.map { attachment -> PersistedAttachmentDraft in
      switch attachment {
      case .shiftSnapshot(let draft):
        return PersistedAttachmentDraft.shiftSnapshot(draft)

      case .image(let image):
        let fileURL = try writeImageAttachment(
          image,
          threadId: threadId,
          viewerUserId: viewerUserId
        )
        let relativePath = fileURL.path.replacingOccurrences(
          of: attachmentsDirectory.path + "/",
          with: ""
        )
        return PersistedAttachmentDraft.image(
          PersistedImageAttachmentDraft(
            id: image.id,
            mediaType: image.mediaType,
            relativePath: relativePath
          )
        )
      }
    }

    pruneAttachmentFiles(
      keeping: Set(
        persistedDrafts.compactMap { persistedDraft in
          guard case .image(let imageDraft) = persistedDraft else {
            return nil
          }
          return imageDraft.relativePath
        }),
      threadId: threadId,
      viewerUserId: viewerUserId
    )

    return try JSONEncoder().encode(persistedDrafts)
  }

  private func materializePersistedAttachmentDrafts(
    _ persistedDrafts: [PersistedAttachmentDraft],
    threadId _: String,
    viewerUserId _: String
  ) throws -> [FriendsComposerAttachmentDraft] {
    try persistedDrafts.compactMap { persistedDraft in
      switch persistedDraft {
      case .shiftSnapshot(let draft):
        return .shiftSnapshot(draft)

      case .image(let imageDraft):
        let fileURL = attachmentsDirectory.appendingPathComponent(imageDraft.relativePath)
        let data = try Data(contentsOf: fileURL)
        return .image(
          ImageAttachment(
            id: imageDraft.id,
            data: data,
            mediaType: imageDraft.mediaType
          )
        )
      }
    }
  }

  private func writeImageAttachment(
    _ image: ImageAttachment,
    threadId: String,
    viewerUserId: String
  ) throws -> URL {
    let draftDirectory = draftAttachmentDirectory(threadId: threadId, viewerUserId: viewerUserId)
    try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)

    let fileURL = draftDirectory.appendingPathComponent(
      "\(image.id).\(fileExtension(for: image.mediaType))"
    )
    try image.data.write(to: fileURL, options: .atomic)
    return fileURL
  }

  private func pruneAttachmentFiles(
    keeping relativePaths: Set<String>,
    threadId: String,
    viewerUserId: String
  ) {
    let draftDirectory = draftAttachmentDirectory(threadId: threadId, viewerUserId: viewerUserId)
    guard
      let fileURLs = try? FileManager.default.contentsOfDirectory(
        at: draftDirectory,
        includingPropertiesForKeys: nil
      )
    else {
      return
    }

    for fileURL in fileURLs {
      let relativePath = fileURL.path.replacingOccurrences(
        of: attachmentsDirectory.path + "/", with: "")
      guard !relativePaths.contains(relativePath) else { continue }
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  private func removeAttachmentFiles(threadId: String, viewerUserId: String) {
    let draftDirectory = draftAttachmentDirectory(threadId: threadId, viewerUserId: viewerUserId)
    try? FileManager.default.removeItem(at: draftDirectory)
  }

  private func draftAttachmentDirectory(threadId: String, viewerUserId: String) -> URL {
    attachmentsDirectory
      .appendingPathComponent(viewerUserId, isDirectory: true)
      .appendingPathComponent(threadId, isDirectory: true)
  }

  private func loadExpiredDraftRecords(olderThan cutoffDate: Date)
    -> [LocalPendingFriendComposerDraft]
  {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<LocalPendingFriendComposerDraft>(
      predicate: #Predicate { $0.updatedAt < cutoffDate }
    )

    return (try? context.fetch(descriptor)) ?? []
  }

  private func ensureAttachmentsDirectoryExists() {
    do {
      try FileManager.default.createDirectory(
        at: attachmentsDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      composerDraftLogger.error(
        "Failed to create composer attachment directory: \(error.localizedDescription)")
    }
  }

  static func resolvedAttachmentsDirectory(appGroupURL: URL?, fallbackBaseURL: URL) -> URL {
    if let appGroupURL {
      return
        appGroupURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent(Storage.directoryName, isDirectory: true)
    }

    return
      fallbackBaseURL
      .appendingPathComponent(Storage.directoryName, isDirectory: true)
  }

  private static func defaultAttachmentsDirectory() -> URL {
    let fileManager = FileManager.default

    let fallbackBaseURL =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory

    return resolvedAttachmentsDirectory(
      appGroupURL: fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: Storage.appGroupId
      ),
      fallbackBaseURL: fallbackBaseURL
    )
  }

  private func fileExtension(for mimeType: String) -> String {
    switch mimeType.lowercased() {
    case "image/png":
      return "png"

    case "image/webp":
      return "webp"

    case "image/heic", "image/heif":
      return "heic"

    default:
      return "jpg"
    }
  }
}
