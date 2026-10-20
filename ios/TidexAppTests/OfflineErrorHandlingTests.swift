import XCTest

@testable import Tidex

@MainActor
final class OfflineErrorHandlingTests: XCTestCase {
  // MARK: - Offline classification

  func testURLErrorsThatMeanNoConnectionAreOffline() {
    XCTAssertTrue(ErrorTranslations.isOffline(URLError(.notConnectedToInternet)))
    XCTAssertTrue(ErrorTranslations.isOffline(URLError(.timedOut)))
    XCTAssertTrue(
      ErrorTranslations.isOffline(
        NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue)))
    XCTAssertFalse(ErrorTranslations.isOffline(URLError(.badURL)))
  }

  func testNonNetworkFailuresAreNotOffline() {
    XCTAssertFalse(
      ErrorTranslations.isOffline(SharingServiceError.networkError(underlying: URLError(.badURL))))
    XCTAssertFalse(ErrorTranslations.isOffline(SharingServiceError.httpError(statusCode: 400, message: "x")))
    XCTAssertFalse(ErrorTranslations.isOffline(SharingServiceError.notAuthenticated))
    XCTAssertFalse(ErrorTranslations.isOffline(FriendsAPIError.unauthorized))
  }

  // MARK: - Share extension errors

  // MARK: - Send to chat

  func testLocalDirectThreadIgnoresRoomsAndOtherUsers() {
    let threads = [
      makeThread(id: "room", kind: .room, counterpartUserId: "friend"),
      makeThread(id: "other", kind: .direct, counterpartUserId: "someone-else"),
      makeThread(id: "match", kind: .direct, counterpartUserId: "friend"),
      makeThread(id: "older-match", kind: .direct, counterpartUserId: "friend"),
    ]

    XCTAssertEqual(
      SendAttachmentRecipientResolver.localDirectThread(for: "friend", in: threads)?.id, "match")
    XCTAssertNil(SendAttachmentRecipientResolver.localDirectThread(for: "stranger", in: threads))
  }

  private func makeThread(id: String, kind: FriendThreadKind, counterpartUserId: String?)
    -> FriendThread
  {
    FriendThread(
      id: id,
      kind: kind,
      title: nil,
      avatarUrl: nil,
      counterpartUserId: counterpartUserId,
      counterpartDisplayName: nil,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: nil,
      lastMessageSenderId: nil,
      lastMessageAt: nil,
      lastMessageBody: nil,
      createdAt: Date(timeIntervalSince1970: 0)
    )
  }
}
