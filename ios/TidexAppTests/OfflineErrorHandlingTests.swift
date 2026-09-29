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

  func testServiceWrappersAreUnwrapped() {
    let offline = URLError(.notConnectedToInternet)

    XCTAssertTrue(ErrorTranslations.isOffline(SharingServiceError.networkError(underlying: offline)))
    XCTAssertTrue(
      ErrorTranslations.isOffline(FriendsMessagingServiceError.networkError(underlying: offline)))
    XCTAssertTrue(ErrorTranslations.isOffline(FriendsAPIError.offline))
    XCTAssertTrue(ErrorTranslations.isOffline(AuthSessionManagerError.sessionFetchTimedOut))
  }

  func testNonNetworkFailuresAreNotOffline() {
    XCTAssertFalse(
      ErrorTranslations.isOffline(SharingServiceError.networkError(underlying: URLError(.badURL))))
    XCTAssertFalse(ErrorTranslations.isOffline(SharingServiceError.httpError(statusCode: 400, message: "x")))
    XCTAssertFalse(ErrorTranslations.isOffline(SharingServiceError.notAuthenticated))
    XCTAssertFalse(ErrorTranslations.isOffline(FriendsAPIError.unauthorized))
  }

  func testTranslateReplacesSystemNetworkTextWithLocalizedCopy() {
    let offline = URLError(.notConnectedToInternet)

    XCTAssertEqual(ErrorTranslations.translate(offline), ErrorTranslations.offlineMessage)
    XCTAssertEqual(
      ErrorTranslations.translate(SharingServiceError.networkError(underlying: offline)),
      ErrorTranslations.offlineMessage
    )
  }

  func testSharingNetworkErrorDescriptionDoesNotEmbedSystemText() {
    let error = SharingServiceError.networkError(
      underlying: URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "SYSTEM TEXT"]))

    XCTAssertFalse((error.errorDescription ?? "").contains("SYSTEM TEXT"))
  }

  // MARK: - Share extension errors

  func testFriendsAPIErrorMapsOfflineTransportFailures() {
    guard case .offline = FriendsAPIError.transportError(URLError(.notConnectedToInternet)) else {
      return XCTFail("Expected .offline")
    }
    guard case .networkError = FriendsAPIError.transportError(URLError(.badURL)) else {
      return XCTFail("Expected .networkError")
    }
  }

  func testFriendsAPIErrorDescriptionsAreLocalizedAndHideDiagnostics() {
    XCTAssertEqual(
      FriendsAPIError.offline.errorDescription, String(localized: .shareErrorOffline))
    XCTAssertEqual(
      FriendsAPIError.noAccessToken.errorDescription, String(localized: .shareErrorSignInRequired))
    XCTAssertEqual(
      FriendsAPIError.unauthorized.errorDescription, String(localized: .shareErrorSignInRequired))

    let diagnostic = "RPC get_share_recipients failed (500): boom"
    XCTAssertEqual(
      FriendsAPIError.networkError(underlying: diagnostic).errorDescription,
      String(localized: .shareErrorRequestFailed)
    )
    XCTAssertEqual(
      FriendsAPIError.httpError(statusCode: 503).errorDescription,
      String(localized: .shareErrorRequestFailed)
    )
  }

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
