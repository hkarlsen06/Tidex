import Foundation
import SwiftData

// MARK: - Local Conversation

// ponytail: dead table kept to avoid a SwiftData migration; drop it with a VersionedSchema migration.
/// Leftover SwiftData model from the removed Wagey chat. It stays in the schema so
/// existing stores open without a migration. `LocalStore.resetAllData()` clears it.
@Model
final class LocalConversation {
  @Attribute(.unique)
  var id: String
  var userId: String
  var title: String
  var messagesData: Data
  var compaction: String?
  var createdAt: Date
  var updatedAt: Date

  init(id: String, userId: String, title: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.userId = userId
    self.title = title
    self.messagesData = Data()
    self.compaction = nil
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
