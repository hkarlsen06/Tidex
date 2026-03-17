import Foundation
import SwiftData

@Model
final class LocalPendingFriendComposerDraft {
  @Attribute(.unique)
  var compositeKey: String
  var viewerUserId: String
  var threadId: String
  var draftText: String?
  var attachmentData: Data?
  var createdAt: Date
  var updatedAt: Date

  init(
    viewerUserId: String,
    threadId: String,
    draftText: String? = nil,
    attachmentData: Data? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerUserId):\(threadId)"
    self.viewerUserId = viewerUserId
    self.threadId = threadId
    self.draftText = draftText
    self.attachmentData = attachmentData
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
