import Foundation
import SwiftData
import os.log

private let composerDraftLogger = Logger(
  subsystem: "com.tidex.app",
  category: "FriendsComposerDraftStore"
)

@MainActor
final class FriendsComposerDraftStore {
  struct Draft: Equatable {
    let text: String
    let attachment: FriendsComposerAttachmentDraft?
  }

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
      guard let localDraft = try context.fetch(descriptor).first else { return nil }
      let text = localDraft.draftText ?? ""
      var attachment: FriendsComposerAttachmentDraft?

      if let attachmentData = localDraft.attachmentData {
        do {
          attachment = try JSONDecoder().decode(
            FriendsComposerAttachmentDraft.self,
            from: attachmentData
          )
        } catch {
          composerDraftLogger.error(
            "Failed to decode pending composer attachment draft: \(error.localizedDescription)")
          await clearAttachmentDraft(threadId: threadId, viewerUserId: viewerUserId)
        }
      }

      let draft = Draft(
        text: text,
        attachment: attachment
      )

      guard !draft.text.isEmpty || draft.attachment != nil else {
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
    await saveDraftText(text, threadId: threadId, viewerUserId: viewerUserId)

    if let attachment {
      await saveAttachmentDraft(attachment, threadId: threadId, viewerUserId: viewerUserId)
    } else {
      await clearAttachmentDraft(threadId: threadId, viewerUserId: viewerUserId)
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
      try await storeActor.savePendingFriendComposerDraftAttachmentData(
        attachmentData,
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
