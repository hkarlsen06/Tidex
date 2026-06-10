import XCTest

@testable import Tidex

@MainActor
final class CalendarSubscriptionStoreTests: XCTestCase {
  func testURLBuilderUsesWebcalForLaunchAndHTTPSForFallback() {
    let service = CalendarSubscriptionService()
    let token = "tidex_cal_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    XCTAssertEqual(
      service.webcalURL(rawToken: token)?.absoluteString,
      "webcal://identity.tidex.no/functions/v1/calendar-feed/\(token).ics"
    )
    XCTAssertEqual(
      service.httpsURL(rawToken: token)?.absoluteString,
      "https://identity.tidex.no/functions/v1/calendar-feed/\(token).ics"
    )
  }

  func testTokenStoreScopesTokensByUserAndSubscription() throws {
    let metadata = makeMetadata(id: "subscription-1", suffix: "aaaaaaaa")
    let otherMetadata = makeMetadata(id: "subscription-2", suffix: "bbbbbbbb")
    let tokenStore = InMemoryCalendarSubscriptionTokenStore()

    try tokenStore.saveToken(
      CalendarSubscriptionKeychainToken(
        userId: "user-1",
        subscriptionId: metadata.id,
        tokenSuffix: metadata.tokenSuffix,
        rawToken: "token-1"
      ))

    XCTAssertEqual(
      tokenStore.loadToken(userId: "user-1", metadata: metadata)?.rawToken,
      "token-1"
    )
    XCTAssertNil(tokenStore.loadToken(userId: "user-2", metadata: metadata))
    XCTAssertNil(tokenStore.loadToken(userId: "user-1", metadata: otherMetadata))
  }

  func testDuplicateCreateRefreshesActiveState() async {
    let activeMetadata = makeMetadata()
    let service = MockCalendarSubscriptionService(
      state: .inactive,
      activeAfterDuplicate: CalendarSubscriptionState(metadata: activeMetadata),
      createError: MockCalendarSubscriptionError.activeAlreadyExists
    )
    let store = CalendarSubscriptionStore(
      service: service,
      tokenStore: InMemoryCalendarSubscriptionTokenStore(),
      userIdProvider: { "user-1" }
    )

    do {
      _ = try await store.create(mode: .shiftsAndEvents)
      XCTFail("Expected duplicate-active error")
    } catch CalendarSubscriptionStoreError.subscriptionAlreadyActive {
      XCTAssertEqual(store.state.metadata, activeMetadata)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testDisableClearsFallbackURL() async throws {
    let metadata = makeMetadata()
    let service = MockCalendarSubscriptionService(
      state: CalendarSubscriptionState(metadata: metadata),
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    let tokenStore = InMemoryCalendarSubscriptionTokenStore()
    let store = CalendarSubscriptionStore(
      service: service,
      tokenStore: tokenStore,
      userIdProvider: { "user-1" }
    )
    store.fallbackHTTPSURL = URL(
      string: "https://identity.tidex.no/functions/v1/calendar-feed/old.ics")

    try await store.disable()

    XCTAssertNil(store.fallbackHTTPSURL)
  }

  private func makeMetadata(
    id: String = "subscription-1",
    suffix: String = "aaaaaaaa"
  ) -> CalendarSubscriptionMetadata {
    CalendarSubscriptionMetadata(
      id: id,
      contentMode: .shiftsAndEvents,
      tokenSuffix: suffix,
      createdAt: "2026-05-15T00:00:00Z",
      updatedAt: "2026-05-15T00:00:00Z",
      lastUsedAt: nil
    )
  }
}

private enum MockCalendarSubscriptionError: Error, LocalizedError {
  case activeAlreadyExists

  var errorDescription: String? {
    switch self {
    case .activeAlreadyExists:
      return "active calendar subscription already exists"
    }
  }
}

private final class MockCalendarSubscriptionService: CalendarSubscriptionServicing {
  var state: CalendarSubscriptionState
  let activeAfterDuplicate: CalendarSubscriptionState
  let createError: Error?

  init(
    state: CalendarSubscriptionState,
    activeAfterDuplicate: CalendarSubscriptionState,
    createError: Error?
  ) {
    self.state = state
    self.activeAfterDuplicate = activeAfterDuplicate
    self.createError = createError
  }

  // swiftlint:disable:next async_without_await
  func getSubscription() async -> CalendarSubscriptionState {
    if createError != nil {
      state = activeAfterDuplicate
    }
    return state
  }

  // swiftlint:disable:next async_without_await
  func createSubscription(mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionCreated
  {
    if let createError {
      throw createError
    }

    let metadata = CalendarSubscriptionMetadata(
      id: "subscription-created",
      contentMode: mode,
      tokenSuffix: "cccccccc",
      createdAt: "2026-05-15T00:00:00Z",
      updatedAt: "2026-05-15T00:00:00Z",
      lastUsedAt: nil
    )
    return CalendarSubscriptionCreated(metadata: metadata, rawToken: "raw-token")
  }

  func rotateSubscription(mode: CalendarSubscriptionContentMode?) async throws
    -> CalendarSubscriptionCreated
  {
    try await createSubscription(mode: mode ?? .shiftsAndEvents)
  }

  // swiftlint:disable:next async_without_await
  func setContentMode(_ mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionMetadata
  {
    guard let metadata = state.metadata else {
      throw CalendarSubscriptionStoreError.noActiveSubscription
    }
    let updated = CalendarSubscriptionMetadata(
      id: metadata.id,
      contentMode: mode,
      tokenSuffix: metadata.tokenSuffix,
      createdAt: metadata.createdAt,
      updatedAt: metadata.updatedAt,
      lastUsedAt: metadata.lastUsedAt
    )
    state = CalendarSubscriptionState(metadata: updated)
    return updated
  }

  // swiftlint:disable:next async_without_await
  func disableSubscription() async -> Bool {
    state = .inactive
    return true
  }

  func webcalURL(rawToken: String) -> URL? {
    URL(string: "webcal://identity.tidex.no/functions/v1/calendar-feed/\(rawToken).ics")
  }

  func httpsURL(rawToken: String) -> URL? {
    URL(string: "https://identity.tidex.no/functions/v1/calendar-feed/\(rawToken).ics")
  }
}

private final class InMemoryCalendarSubscriptionTokenStore: CalendarSubscriptionTokenStoring {
  private var tokens: [String: CalendarSubscriptionKeychainToken] = [:]

  func loadToken(userId: String, metadata: CalendarSubscriptionMetadata)
    -> CalendarSubscriptionKeychainToken?
  {
    tokens[key(userId: userId, subscriptionId: metadata.id)]
  }

  func saveToken(_ token: CalendarSubscriptionKeychainToken) {
    tokens[key(userId: token.userId, subscriptionId: token.subscriptionId)] = token
  }

  func deleteToken(userId: String, metadata: CalendarSubscriptionMetadata) {
    tokens.removeValue(forKey: key(userId: userId, subscriptionId: metadata.id))
  }

  func clearAllTokens() {
    tokens.removeAll()
  }

  private func key(userId: String, subscriptionId: String) -> String {
    "\(userId):\(subscriptionId)"
  }
}
