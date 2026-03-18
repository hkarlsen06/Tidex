import Foundation
import SwiftData

extension LocalStoreActor {
  func savePendingFriendComposerDraftText(
    _ draftText: String,
    threadId: String,
    viewerUserId: String
  ) throws {
    let draft =
      try pendingFriendComposerDraft(threadId: threadId, viewerUserId: viewerUserId)
      ?? LocalPendingFriendComposerDraft(
        viewerUserId: viewerUserId,
        threadId: threadId
      )

    if draft.modelContext == nil {
      modelContext.insert(draft)
    }

    draft.draftText = draftText
    draft.updatedAt = Date()
    try deletePendingFriendComposerDraftIfEmpty(draft)
    try modelContext.save()
  }

  func clearPendingFriendComposerDraftText(threadId: String, viewerUserId: String) throws {
    guard
      let existing = try pendingFriendComposerDraft(
        threadId: threadId,
        viewerUserId: viewerUserId
      )
    else {
      return
    }

    existing.draftText = nil
    existing.updatedAt = Date()
    try deletePendingFriendComposerDraftIfEmpty(existing)
    try modelContext.save()
  }

  func savePendingFriendComposerDraftAttachmentData(
    _ attachmentData: Data,
    threadId: String,
    viewerUserId: String
  ) throws {
    let draft =
      try pendingFriendComposerDraft(threadId: threadId, viewerUserId: viewerUserId)
      ?? LocalPendingFriendComposerDraft(
        viewerUserId: viewerUserId,
        threadId: threadId
      )

    if draft.modelContext == nil {
      modelContext.insert(draft)
    }

    draft.attachmentData = attachmentData
    draft.updatedAt = Date()
    try deletePendingFriendComposerDraftIfEmpty(draft)
    try modelContext.save()
  }

  func clearPendingFriendComposerDraftAttachmentData(threadId: String, viewerUserId: String) throws
  {
    guard
      let existing = try pendingFriendComposerDraft(
        threadId: threadId,
        viewerUserId: viewerUserId
      )
    else {
      return
    }

    existing.attachmentData = nil
    existing.updatedAt = Date()
    try deletePendingFriendComposerDraftIfEmpty(existing)
    try modelContext.save()
  }

  func clearPendingFriendComposerDraft(threadId: String, viewerUserId: String) throws {
    for existing in try pendingFriendComposerDrafts(threadId: threadId, viewerUserId: viewerUserId)
    {
      modelContext.delete(existing)
    }

    try modelContext.save()
  }

  func clearExpiredPendingFriendComposerDrafts(olderThan cutoffDate: Date) throws {
    let descriptor = FetchDescriptor<LocalPendingFriendComposerDraft>(
      predicate: #Predicate { $0.updatedAt < cutoffDate }
    )

    for existing in try modelContext.fetch(descriptor) {
      modelContext.delete(existing)
    }

    try modelContext.save()
  }

  private func pendingFriendComposerDraft(threadId: String, viewerUserId: String) throws
    -> LocalPendingFriendComposerDraft?
  {
    try pendingFriendComposerDrafts(threadId: threadId, viewerUserId: viewerUserId).first
  }

  private func pendingFriendComposerDrafts(threadId: String, viewerUserId: String) throws
    -> [LocalPendingFriendComposerDraft]
  {
    let compositeKey = "\(viewerUserId):\(threadId)"
    let descriptor = FetchDescriptor<LocalPendingFriendComposerDraft>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )

    return try modelContext.fetch(descriptor)
  }

  private func deletePendingFriendComposerDraftIfEmpty(_ draft: LocalPendingFriendComposerDraft)
    throws
  {
    let hasDraftText = !(draft.draftText?.isEmpty ?? true)
    if !hasDraftText, draft.attachmentData == nil {
      modelContext.delete(draft)
    }
  }

  func saveThreadSummaries(_ threads: [FriendThread], for viewerUserId: String) throws {
    try reconcileMissingThreads(keeping: threads.map(\.id), for: viewerUserId)
    for thread in threads {
      try saveThreadSummary(thread, for: viewerUserId)
    }
    try modelContext.save()
  }

  func saveThreadSummary(_ thread: FriendThread, for viewerUserId: String) throws {
    let threadId = thread.id
    let descriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == threadId && localThread.viewerUserId == viewerUserId
      }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      existing.apply(thread: thread)
    } else {
      modelContext.insert(
        LocalThread(
          id: threadId,
          viewerUserId: viewerUserId,
          kindRaw: thread.kind.rawValue,
          title: thread.title,
          avatarUrl: thread.avatarUrl,
          metadataData: thread.metadataData ?? Data(),
          counterpartUserId: thread.counterpartUserId,
          counterpartDisplayName: thread.counterpartDisplayName,
          counterpartProfilePictureUrl: thread.counterpartProfilePictureUrl,
          counterpartOAuthAvatarUrl: thread.counterpartOAuthAvatarUrl,
          lastMessageId: thread.lastMessageId,
          lastMessageSenderId: thread.lastMessageSenderId,
          lastMessageAt: thread.lastMessageAt,
          lastMessageBody: thread.lastMessageBody,
          lastMessagePreviewKindRaw: thread.lastMessagePreviewKind?.rawValue,
          lastMessageHasImage: thread.lastMessageHasImage,
          unreadCount: thread.unreadCount,
          muted: thread.muted,
          createdAt: thread.createdAt
        ))
    }

    try upsertThreadState(
      FriendThreadState(
        threadId: thread.id,
        userId: viewerUserId,
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: thread.muted,
        updatedAt: Date()
      ),
      updateReadMarker: false
    )
  }

  func saveMessages(_ messages: [FriendMessage], in threadId: String, for viewerUserId: String)
    throws
  {
    for message in messages {
      try saveMessage(message, in: threadId, for: viewerUserId)
    }
    try modelContext.save()
  }

  func saveMessage(_ message: FriendMessage, in threadId: String, for viewerUserId: String) throws {
    var storedMessage = message

    if let existing = try fetchMessage(id: message.id, viewerUserId: viewerUserId) {
      storedMessage = mergedMessagePreservingLocalOrdering(
        incoming: message,
        existing: existing,
        viewerUserId: viewerUserId
      )
      existing.apply(message: storedMessage)
    } else if message.senderUserId == viewerUserId,
      let existing = try findReplaceableLocalMessage(
        for: message,
        in: threadId,
        viewerUserId: viewerUserId
      )
    {
      storedMessage = try confirmStoredMessage(
        message,
        replacing: existing,
        in: threadId,
        viewerUserId: viewerUserId
      )
    } else {
      insertMessage(message, in: threadId, for: viewerUserId)
    }

    try deleteConflictingMessages(
      matchingClientId: storedMessage.clientId,
      threadId: threadId,
      viewerUserId: viewerUserId,
      keepingMessageId: storedMessage.id
    )
    try replaceAttachments(for: storedMessage, viewerUserId: viewerUserId)
    try replaceReactions(for: storedMessage, viewerUserId: viewerUserId)
    try updateThreadPreviewIfNeeded(for: storedMessage, viewerUserId: viewerUserId)
  }

  func saveOptimisticMessage(
    _ message: FriendMessage, in threadId: String, for viewerUserId: String
  )
    throws
  {
    try saveMessage(message, in: threadId, for: viewerUserId)
    try modelContext.save()
  }

  func saveConfirmedMessage(
    _ message: FriendMessage,
    replacingLocalMessageId localMessageId: String,
    in threadId: String,
    for viewerUserId: String
  ) throws {
    _ = localMessageId
    try saveMessage(message, in: threadId, for: viewerUserId)
    try modelContext.save()
  }

  func deleteMessage(id: String, viewerUserId: String) throws {
    guard let message = try fetchMessage(id: id, viewerUserId: viewerUserId) else { return }
    let threadId = message.threadId
    try deleteStoredMessage(id: id, viewerUserId: viewerUserId)
    try refreshThreadPreviewAfterDeletingMessage(
      threadId: threadId,
      deletedMessageId: id,
      viewerUserId: viewerUserId
    )
    try modelContext.save()
  }

  func updateMessageSendState(
    messageId: String,
    viewerUserId: String,
    sendState: FriendMessageSendState,
    failureMessage: String?
  ) throws {
    guard let message = try fetchMessage(id: messageId, viewerUserId: viewerUserId) else { return }
    message.sendStateRaw = sendState.rawValue
    message.failureMessage = failureMessage
    message.updatedAt = Date()
    try modelContext.save()
  }

  func saveThreadState(_ state: FriendThreadState) throws {
    try upsertThreadState(state, updateReadMarker: true)
    try modelContext.save()
  }

  private func upsertThreadState(_ state: FriendThreadState, updateReadMarker: Bool) throws {
    let stateUserId = state.userId
    let stateThreadId = state.threadId
    let compositeKey = "\(stateUserId):\(stateThreadId)"
    let descriptor = FetchDescriptor<LocalThreadState>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      if updateReadMarker {
        existing.apply(state: state)
      } else {
        existing.muted = state.muted
        existing.updatedAt = state.updatedAt
      }
    } else {
      modelContext.insert(
        LocalThreadState(
          threadId: stateThreadId,
          userId: stateUserId,
          lastReadMessageId: updateReadMarker ? state.lastReadMessageId : nil,
          lastReadAt: updateReadMarker ? state.lastReadAt : nil,
          muted: state.muted,
          updatedAt: state.updatedAt
        ))
    }

    let threadDescriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == stateThreadId && localThread.viewerUserId == stateUserId
      }
    )

    if let localThread = try modelContext.fetch(threadDescriptor).first {
      localThread.muted = state.muted
      if updateReadMarker, state.lastReadMessageId != nil {
        localThread.unreadCount = 0
      }
      localThread.updatedAt = Date()
    }
  }

  private func replaceAttachments(for message: FriendMessage, viewerUserId: String) throws {
    try deleteAttachments(messageId: message.id, viewerUserId: viewerUserId)

    for attachment in message.attachments {
      modelContext.insert(
        LocalMessageAttachment(
          id: attachment.id,
          viewerUserId: viewerUserId,
          threadId: message.threadId,
          messageId: message.id,
          attachmentIndex: attachment.attachmentIndex,
          kindRaw: attachment.kind.rawValue,
          storageBucket: attachment.storageBucket,
          storagePath: attachment.storagePath,
          mimeType: attachment.mimeType,
          byteSize: attachment.byteSize,
          width: attachment.width,
          height: attachment.height,
          createdAt: attachment.createdAt
        ))
    }
  }

  private func replaceReactions(for message: FriendMessage, viewerUserId: String) throws {
    try deleteReactions(messageId: message.id, viewerUserId: viewerUserId)

    for (index, reaction) in message.reactions.enumerated() {
      modelContext.insert(
        LocalMessageReaction(
          viewerUserId: viewerUserId,
          threadId: message.threadId,
          messageId: message.id,
          reactionIndex: index,
          emoji: reaction.emoji,
          count: reaction.count,
          viewerHasReacted: reaction.viewerHasReacted
        ))
    }
  }

  private func updateThreadPreviewIfNeeded(for message: FriendMessage, viewerUserId: String) throws
  {
    let threadId = message.threadId
    let descriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == threadId && localThread.viewerUserId == viewerUserId
      }
    )

    guard let thread = try modelContext.fetch(descriptor).first else { return }

    let shouldReplacePreview: Bool
    if let existingDate = thread.lastMessageAt, let existingId = thread.lastMessageId {
      shouldReplacePreview = (message.createdAt, message.id) >= (existingDate, existingId)
    } else {
      shouldReplacePreview = true
    }

    guard shouldReplacePreview else { return }

    thread.lastMessageId = message.id
    thread.lastMessageSenderId = message.senderUserId
    thread.lastMessageAt = message.createdAt
    thread.lastMessageBody = message.body
    thread.lastMessagePreviewKindRaw = message.previewKind.rawValue
    thread.lastMessageHasImage = message.hasImageAttachment
    thread.sortTimestamp = message.createdAt
    thread.updatedAt = Date()
  }

  private func confirmStoredMessage(
    _ message: FriendMessage,
    replacing localMessage: LocalMessage,
    in threadId: String,
    viewerUserId: String
  ) throws -> FriendMessage {
    let previousMessageId = localMessage.id
    let confirmedMessage = FriendMessage(
      id: message.id,
      threadId: message.threadId,
      senderUserId: message.senderUserId,
      messageType: message.messageType,
      body: message.body,
      clientId: message.clientId,
      replyToMessageId: message.replyToMessageId,
      createdAt: localMessage.createdAt,
      editedAt: message.editedAt,
      deletedAt: message.deletedAt,
      metadataData: message.metadataData,
      attachments: message.attachments,
      reactions: message.reactions,
      sendState: message.sendState,
      failureMessage: message.failureMessage
    )

    if let existingConfirmedMessage = try fetchMessage(id: message.id, viewerUserId: viewerUserId),
      existingConfirmedMessage !== localMessage
    {
      try deleteStoredMessage(id: message.id, viewerUserId: viewerUserId)
    }

    try deleteAttachments(messageId: previousMessageId, viewerUserId: viewerUserId)
    try deleteReactions(messageId: previousMessageId, viewerUserId: viewerUserId)

    localMessage.id = confirmedMessage.id
    localMessage.compositeKey = "\(viewerUserId):\(confirmedMessage.id)"
    localMessage.apply(message: confirmedMessage)

    try updateThreadMessageReferencesIfNeeded(
      from: previousMessageId,
      to: confirmedMessage.id,
      in: threadId,
      viewerUserId: viewerUserId
    )

    return confirmedMessage
  }

  private func mergedMessagePreservingLocalOrdering(
    incoming message: FriendMessage,
    existing localMessage: LocalMessage,
    viewerUserId: String
  ) -> FriendMessage {
    guard
      shouldPreserveLocalCreatedAt(for: message, existing: localMessage, viewerUserId: viewerUserId)
    else {
      return message
    }

    return FriendMessage(
      id: message.id,
      threadId: message.threadId,
      senderUserId: message.senderUserId,
      messageType: message.messageType,
      body: message.body,
      clientId: message.clientId,
      replyToMessageId: message.replyToMessageId,
      createdAt: localMessage.createdAt,
      editedAt: message.editedAt,
      deletedAt: message.deletedAt,
      metadataData: message.metadataData,
      attachments: message.attachments,
      reactions: message.reactions,
      sendState: message.sendState,
      failureMessage: message.failureMessage
    )
  }

  private func shouldPreserveLocalCreatedAt(
    for message: FriendMessage,
    existing localMessage: LocalMessage,
    viewerUserId: String
  ) -> Bool {
    guard message.senderUserId == viewerUserId, localMessage.senderUserId == viewerUserId else {
      return false
    }

    let normalizedIncomingClientId = normalizedClientId(message.clientId)
    let normalizedExistingClientId = normalizedClientId(localMessage.clientId)

    guard
      !normalizedIncomingClientId.isEmpty,
      normalizedIncomingClientId == normalizedExistingClientId
    else {
      return false
    }

    return localMessage.createdAt != message.createdAt
  }

  private func normalizedClientId(_ clientId: String) -> String {
    clientId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func updateThreadMessageReferencesIfNeeded(
    from previousMessageId: String,
    to confirmedMessageId: String,
    in threadId: String,
    viewerUserId: String
  ) throws {
    guard previousMessageId != confirmedMessageId else { return }

    let threadDescriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == threadId && localThread.viewerUserId == viewerUserId
      }
    )

    if let thread = try modelContext.fetch(threadDescriptor).first,
      thread.lastMessageId == previousMessageId
    {
      thread.lastMessageId = confirmedMessageId
      thread.updatedAt = Date()
    }

    let stateDescriptor = FetchDescriptor<LocalThreadState>(
      predicate: #Predicate { localState in
        localState.threadId == threadId && localState.userId == viewerUserId
      }
    )

    if let threadState = try modelContext.fetch(stateDescriptor).first,
      threadState.lastReadMessageId == previousMessageId
    {
      threadState.lastReadMessageId = confirmedMessageId
      threadState.updatedAt = Date()
    }
  }

  private func fetchMessage(id: String, viewerUserId: String) throws -> LocalMessage? {
    let descriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.id == id && localMessage.viewerUserId == viewerUserId
      }
    )
    return try modelContext.fetch(descriptor).first
  }

  private func fetchMessage(
    clientId: String,
    threadId: String,
    viewerUserId: String
  ) throws -> LocalMessage? {
    let descriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.clientId == clientId
          && localMessage.threadId == threadId
          && localMessage.viewerUserId == viewerUserId
      }
    )
    return try modelContext.fetch(descriptor).first
  }

  private func fetchMessages(
    clientId: String,
    threadId: String,
    viewerUserId: String
  ) throws -> [LocalMessage] {
    let descriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.clientId == clientId
          && localMessage.threadId == threadId
          && localMessage.viewerUserId == viewerUserId
      }
    )
    return try modelContext.fetch(descriptor)
  }

  private func findReplaceableLocalMessage(
    for message: FriendMessage,
    in threadId: String,
    viewerUserId: String
  ) throws -> LocalMessage? {
    let normalizedClientId = message.clientId.lowercased()
    guard !normalizedClientId.isEmpty else { return nil }
    return try fetchMessage(
      clientId: normalizedClientId,
      threadId: threadId,
      viewerUserId: viewerUserId
    )
  }

  private func deleteConflictingMessages(
    matchingClientId clientId: String,
    threadId: String,
    viewerUserId: String,
    keepingMessageId: String
  ) throws {
    let normalizedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedClientId.isEmpty else { return }

    let conflictingMessages = try fetchMessages(
      clientId: normalizedClientId,
      threadId: threadId,
      viewerUserId: viewerUserId
    )

    for conflictingMessage in conflictingMessages where conflictingMessage.id != keepingMessageId {
      try deleteStoredMessage(id: conflictingMessage.id, viewerUserId: viewerUserId)
    }
  }

  private func insertMessage(
    _ message: FriendMessage, in threadId: String, for viewerUserId: String
  ) {
    modelContext.insert(
      LocalMessage(
        id: message.id,
        viewerUserId: viewerUserId,
        threadId: threadId,
        senderUserId: message.senderUserId,
        messageTypeRaw: message.messageType.rawValue,
        body: message.body,
        clientId: message.clientId.lowercased(),
        replyToMessageId: message.replyToMessageId,
        createdAt: message.createdAt,
        editedAt: message.editedAt,
        deletedAt: message.deletedAt,
        metadataData: message.metadataData ?? Data(),
        sendStateRaw: message.sendState.rawValue,
        failureMessage: message.failureMessage
      ))
  }

  private func deleteAttachments(messageId: String, viewerUserId: String) throws {
    let descriptor = FetchDescriptor<LocalMessageAttachment>(
      predicate: #Predicate { attachment in
        attachment.messageId == messageId && attachment.viewerUserId == viewerUserId
      }
    )

    for existing in try modelContext.fetch(descriptor) {
      modelContext.delete(existing)
    }
  }

  private func deleteReactions(messageId: String, viewerUserId: String) throws {
    let descriptor = FetchDescriptor<LocalMessageReaction>(
      predicate: #Predicate { reaction in
        reaction.messageId == messageId && reaction.viewerUserId == viewerUserId
      }
    )

    for existing in try modelContext.fetch(descriptor) {
      modelContext.delete(existing)
    }
  }

  private func deleteStoredMessage(id: String, viewerUserId: String) throws {
    guard let message = try fetchMessage(id: id, viewerUserId: viewerUserId) else { return }
    try deleteAttachments(messageId: id, viewerUserId: viewerUserId)
    try deleteReactions(messageId: id, viewerUserId: viewerUserId)
    modelContext.delete(message)
  }

  private func refreshThreadPreviewAfterDeletingMessage(
    threadId: String,
    deletedMessageId: String,
    viewerUserId: String
  ) throws {
    let threadDescriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == threadId && localThread.viewerUserId == viewerUserId
      }
    )

    guard let thread = try modelContext.fetch(threadDescriptor).first else { return }
    guard thread.lastMessageId == deletedMessageId else { return }

    let latestMessageDescriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.threadId == threadId && localMessage.viewerUserId == viewerUserId
      },
      sortBy: [
        SortDescriptor(\LocalMessage.createdAt, order: .reverse),
        SortDescriptor(\LocalMessage.id, order: .reverse),
      ]
    )

    guard let latestMessage = try modelContext.fetch(latestMessageDescriptor).first else {
      thread.lastMessageId = nil
      thread.lastMessageSenderId = nil
      thread.lastMessageAt = nil
      thread.lastMessageBody = nil
      thread.lastMessagePreviewKindRaw = nil
      thread.lastMessageHasImage = false
      thread.sortTimestamp = thread.createdAt
      thread.updatedAt = Date()
      return
    }

    let latestMessageId = latestMessage.id
    let attachmentDescriptor = FetchDescriptor<LocalMessageAttachment>(
      predicate: #Predicate { attachment in
        attachment.messageId == latestMessageId && attachment.viewerUserId == viewerUserId
      },
      sortBy: [
        SortDescriptor(\LocalMessageAttachment.attachmentIndex, order: .forward),
        SortDescriptor(\LocalMessageAttachment.id, order: .forward),
      ]
    )

    let latestFriendMessage = latestMessage.toFriendMessage(
      attachments: try modelContext.fetch(attachmentDescriptor),
      reactions: []
    )

    thread.lastMessageId = latestFriendMessage.id
    thread.lastMessageSenderId = latestFriendMessage.senderUserId
    thread.lastMessageAt = latestFriendMessage.createdAt
    thread.lastMessageBody = latestFriendMessage.body
    thread.lastMessagePreviewKindRaw = latestFriendMessage.previewKind.rawValue
    thread.lastMessageHasImage = latestFriendMessage.hasImageAttachment
    thread.sortTimestamp = latestFriendMessage.createdAt
    thread.updatedAt = Date()
  }

  private func reconcileMissingThreads(keeping threadIds: [String], for viewerUserId: String) throws
  {
    let descriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { $0.viewerUserId == viewerUserId }
    )
    let idsToKeep = Set(threadIds)

    for existingThread in try modelContext.fetch(descriptor)
    where !idsToKeep.contains(existingThread.id) {
      try deleteThread(id: existingThread.id, viewerUserId: viewerUserId)
    }
  }

  private func deleteThread(id: String, viewerUserId: String) throws {
    let threadDescriptor = FetchDescriptor<LocalThread>(
      predicate: #Predicate { localThread in
        localThread.id == id && localThread.viewerUserId == viewerUserId
      }
    )

    if let existingThread = try modelContext.fetch(threadDescriptor).first {
      modelContext.delete(existingThread)
    }

    let threadStateCompositeKey = "\(viewerUserId):\(id)"
    let threadStateDescriptor = FetchDescriptor<LocalThreadState>(
      predicate: #Predicate { $0.compositeKey == threadStateCompositeKey }
    )
    for existingState in try modelContext.fetch(threadStateDescriptor) {
      modelContext.delete(existingState)
    }

    let messageDescriptor = FetchDescriptor<LocalMessage>(
      predicate: #Predicate { localMessage in
        localMessage.threadId == id && localMessage.viewerUserId == viewerUserId
      }
    )
    let messageIds = try modelContext.fetch(messageDescriptor).map(\.id)
    for messageId in messageIds {
      try deleteStoredMessage(id: messageId, viewerUserId: viewerUserId)
    }
  }
}
