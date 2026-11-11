import XCTest

@testable import Tidex

/// Who sees whose shifts through invite links: a link never shares anything on its own, a
/// pending invite stays with the account that opened it, and refusals say why.
@MainActor
internal final class FriendInviteTests: XCTestCase {
  private let inviterId = "0b7e3f2a-5c1d-4e8f-9a6b-2d4c8e1f3a5b"
  private let viewerId = "7c2d9e4f-1a3b-4c5d-8e6f-9a0b1c2d3e4f"

  private struct Share: Equatable {
    let recipientId: String
    let showEarnings: Bool
  }

  @MainActor
  private final class Network {
    var isOnline = false
  }

  // MARK: - Pending invite

  internal func testInviteOpenedByOneAccountIsNeverShownToAnother() {
    let defaults = makeDefaults()
    PendingInviteStore.save(inviterId: inviterId, openedBy: "account-a", defaults: defaults)

    XCTAssertNil(PendingInviteStore.inviter(for: "account-b", defaults: defaults))
    XCTAssertNil(
      PendingInviteStore.inviter(for: "account-a", defaults: defaults),
      "dropped once another account saw it, so a later sign-in cannot pick it up")
  }

  internal func testInviteOpenedBySignedInAccountWaitsForThatAccount() {
    let defaults = makeDefaults()
    PendingInviteStore.save(inviterId: inviterId, openedBy: viewerId, defaults: defaults)

    XCTAssertEqual(PendingInviteStore.inviter(for: viewerId, defaults: defaults), inviterId)
  }

  internal func testInviteOpenedWhileSignedOutGoesToWhoeverSignsInUntilHandled() {
    let defaults = makeDefaults()
    PendingInviteStore.save(inviterId: inviterId, openedBy: nil, defaults: defaults)

    XCTAssertEqual(PendingInviteStore.inviter(for: viewerId, defaults: defaults), inviterId)
    PendingInviteStore.clear(defaults: defaults)
    XCTAssertNil(PendingInviteStore.inviter(for: viewerId, defaults: defaults))
  }

  // MARK: - Confirmation

  internal func testOpeningAnInviteSharesNothingUntilTheUserConfirms() async {
    var shares: [Share] = []
    let model = makeModel(preview: preview()) { shares.append($0) }

    await model.load()
    XCTAssertEqual(model.phase, .confirm(preview(), .idle))
    XCTAssertEqual(shares, [])

    let started = await model.confirm()
    XCTAssertTrue(started)
    XCTAssertEqual(shares, [Share(recipientId: inviterId, showEarnings: false)])
    XCTAssertEqual(model.phase, .shared(preview()))
  }

  internal func testEarningsAreSharedOnlyWhenTheUserTurnsThemOn() async {
    var shares: [Share] = []
    let model = makeModel(preview: preview()) { shares.append($0) }

    await model.load()
    model.showEarnings = true
    await model.confirm()

    XCTAssertEqual(shares, [Share(recipientId: inviterId, showEarnings: true)])
  }

  internal func testOwnLinkNeverAsksTheServerOrShares() async {
    var shares: [Share] = []
    var previewLoads = 0
    let model = InviteConfirmationModel(
      inviterId: viewerId, viewerId: viewerId,
      loadPreview: { _ in
        previewLoads += 1
        return nil
      },
      share: { shares.append(Share(recipientId: $0, showEarnings: $1)) })

    await model.load()
    let started = await model.confirm()

    XCTAssertEqual(model.phase, .ownLink)
    XCTAssertFalse(started)
    XCTAssertEqual(previewLoads, 0)
    XCTAssertEqual(shares, [])
  }

  internal func testUnknownOrBlockedInviterCannotBeSharedWith() async {
    var shares: [Share] = []
    let model = makeModel(preview: nil) { shares.append($0) }

    await model.load()
    let started = await model.confirm()

    XCTAssertEqual(model.phase, .unavailable)
    XCTAssertFalse(started)
    XCTAssertEqual(shares, [])
  }

  internal func testUnloadablePreviewNeverOffersToShareUntilARetrySucceeds() async {
    var shares: [Share] = []
    let network = Network()
    let model = InviteConfirmationModel(
      inviterId: inviterId, viewerId: viewerId,
      loadPreview: { [preview = preview()] _ in
        guard network.isOnline else { throw URLError(.notConnectedToInternet) }
        return preview
      },
      share: { shares.append(Share(recipientId: $0, showEarnings: $1)) })

    await model.load()
    let startedOffline = await model.confirm()
    XCTAssertEqual(model.phase, .loadFailed)
    XCTAssertFalse(startedOffline)

    network.isOnline = true
    await model.load()
    await model.confirm()
    XCTAssertEqual(shares, [Share(recipientId: inviterId, showEarnings: false)])
  }

  internal func testAnExistingShareIsReportedInsteadOfSharedAgain() async {
    var shares: [Share] = []
    let existing = preview(alreadySharing: true)
    let model = makeModel(preview: existing) { shares.append($0) }

    await model.load()
    let started = await model.confirm()

    XCTAssertEqual(model.phase, .alreadySharing(existing))
    XCTAssertFalse(started)
    XCTAssertEqual(shares, [])
  }

  // MARK: - Failure codes

  internal func testEachShareFailureCodeShowsItsOwnMessage() throws {
    let expected: [(String, LocalizedStringResource)] = [
      ("no_identifier", .sharingErrorNoIdentifier),
      ("not_found", .sharingErrorNotFound),
      ("self", .sharingErrorSelf),
      ("blocked", .sharingErrorBlocked),
      ("exists", .sharingErrorExists),
    ]
    for (code, message) in expected {
      XCTAssertEqual(
        try translatedReply(#"{"success":false,"code":"\#(code)","error":"Norsk tekst"}"#),
        String(localized: message), code)
    }
  }

  internal func testFailureWithoutAKnownCodeFallsBackToTheGenericMessage() throws {
    for reply in [
      #"{"success":false,"error":"Norsk tekst"}"#,
      #"{"success":false,"code":"something_new","error":"Norsk tekst"}"#,
    ] {
      XCTAssertEqual(try translatedReply(reply), String(localized: .sharingErrorAddFriend), reply)
    }
  }

  internal func testSuccessfulReplyIsNoError() throws {
    let reply = try JSONDecoder().decode(
      ManageActionResponse.self, from: Data(#"{"success":true}"#.utf8))
    XCTAssertNil(SharingService.shareError(for: reply))
  }

  // MARK: - Helpers

  private func translatedReply(_ json: String) throws -> String? {
    let reply = try JSONDecoder().decode(ManageActionResponse.self, from: Data(json.utf8))
    let error = try XCTUnwrap(SharingService.shareError(for: reply))
    return ErrorTranslations.translate(error, fallback: .sharingErrorAddFriend)
  }

  private func preview(alreadySharing: Bool = false) -> InvitePreview {
    InvitePreview(
      id: inviterId, firstName: "Ola", username: "ola", profilePictureUrl: nil,
      oauthAvatarUrl: nil, alreadySharing: alreadySharing)
  }

  private func makeModel(
    preview: InvitePreview?, onShare: @escaping (Share) -> Void
  ) -> InviteConfirmationModel {
    InviteConfirmationModel(
      inviterId: inviterId, viewerId: viewerId,
      loadPreview: { _ in preview },
      share: { onShare(Share(recipientId: $0, showEarnings: $1)) })
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "FriendInviteTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
