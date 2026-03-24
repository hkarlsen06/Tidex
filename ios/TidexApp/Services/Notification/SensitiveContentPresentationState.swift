import Foundation

@MainActor
final class SensitiveContentPresentationState {
  enum VisibleContext: Equatable {
    case friendThread(threadId: String)
  }

  static let shared = SensitiveContentPresentationState()

  private(set) var visibleContext: VisibleContext?

  var isSensitiveContentVisible: Bool {
    visibleContext != nil
  }

  var activeFriendThreadId: String? {
    guard case .friendThread(let threadId) = visibleContext else { return nil }
    return threadId
  }

  private init() {}

  func setVisibleContext(_ context: VisibleContext?) {
    visibleContext = context
  }
}
