import Foundation
import SwiftData
import os.log

private let composerDraftLogger = Logger(
  subsystem: "com.tidex.app",
  category: "FriendsComposerDraftStore"
)

@MainActor
final class FriendsComposerDraftStore {
  static let shared = FriendsComposerDraftStore()

  private enum Expiry {
    static let interval: TimeInterval = 60 * 60 * 24 * 7
  }

  private let container: ModelContainer
  private let storeActor: LocalStoreActor

  init(container: ModelContainer? = nil, storeActor: LocalStoreActor? = nil) {
    if let container, let storeActor {
      self.container = container
      self.storeActor = storeActor
    } else {
      self.container = LocalStore.shared.container
      self.storeActor = LocalStore.shared.storeActor
    }
  }

  func loadAttachmentDraft(
    threadId: String,
    viewerUserId: String
  ) async -> FriendsComposerAttachmentDraft? {
    await clearExpiredDrafts()

    let context = ModelContext(container)
    let compositeKey = "\(viewerUserId):\(threadId)"
    let descriptor = FetchDescriptor<LocalPendingFriendComposerDraft>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )

    do {
      guard let localDraft = try context.fetch(descriptor).first else { return nil }
      return try JSONDecoder().decode(
        FriendsComposerAttachmentDraft.self,
        from: localDraft.attachmentData
      )
    } catch {
      composerDraftLogger.error(
        "Failed to load pending composer draft: \(error.localizedDescription)")
      await clearAttachmentDraft(threadId: threadId, viewerUserId: viewerUserId)
      return nil
    }
  }

  func saveAttachmentDraft(
    _ attachment: FriendsComposerAttachmentDraft,
    threadId: String,
    viewerUserId: String
  ) async {
    await clearExpiredDrafts()

    do {
      let attachmentData = try JSONEncoder().encode(attachment)
      try await storeActor.savePendingFriendComposerDraft(
        attachmentData: attachmentData,
        threadId: threadId,
        viewerUserId: viewerUserId
      )
    } catch {
      composerDraftLogger.error(
        "Failed to save pending composer draft: \(error.localizedDescription)")
    }
  }

  func clearAttachmentDraft(threadId: String, viewerUserId: String) async {
    do {
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
      try await storeActor.clearExpiredPendingFriendComposerDrafts(
        olderThan: referenceDate.addingTimeInterval(-Expiry.interval)
      )
    } catch {
      composerDraftLogger.error(
        "Failed to clear expired composer drafts: \(error.localizedDescription)")
    }
  }
}
