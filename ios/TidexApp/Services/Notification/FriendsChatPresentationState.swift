import Foundation

@MainActor
final class FriendsChatPresentationState {
  static let shared = FriendsChatPresentationState()

  private(set) var activeThreadId: String?

  private init() {}

  func setActiveThreadId(_ threadId: String?) {
    activeThreadId = threadId
  }
}
