import XCTest

@testable import Tidex

@MainActor
final class CalendarSubscriptionStoreTests: XCTestCase {
  func testLaunchDoesNotOfferSetupWhileSubscriptionStateIsStillLoading() async {
    let service = MockCalendarSubscriptionService(
      state: .inactive, activeAfterDuplicate: .inactive, createError: nil
    )
    let started = expectation(description: "Subscription request started")
    var reply: CheckedContinuation<CalendarSubscriptionState, Error>?
    service.getOverride = {
      try await withCheckedThrowingContinuation {
        reply = $0
        started.fulfill()
      }
    }
    let store = makeStore(service: service, defaults: makeDefaults())
    let refresh = Task { await store.refreshIfNeeded() }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertFalse(store.canOfferSetup)
    reply?.resume(returning: CalendarSubscriptionState(metadata: makeMetadata()))
    await refresh.value
    XCTAssertTrue(store.isActive)
    XCTAssertFalse(store.canOfferSetup)
  }

  func testOldAccountsPendingRefreshCannotReplaceTheNewAccountsState() async {
    let defaults = makeDefaults()
    let service = MockCalendarSubscriptionService(
      state: .inactive, activeAfterDuplicate: .inactive, createError: nil
    )
    let started = expectation(description: "Old account request started")
    var reply: CheckedContinuation<CalendarSubscriptionState, Error>?
    service.getOverride = {
      try await withCheckedThrowingContinuation {
        reply = $0
        started.fulfill()
      }
    }
    var userId = "old-user"
    let store = CalendarSubscriptionStore(
      service: service, tokenStore: InMemoryCalendarSubscriptionTokenStore(),
      defaults: defaults, userIdProvider: { userId }
    )
    let oldRefresh = Task { await store.refresh() }
    await fulfillment(of: [started], timeout: 2)
    store.resetForUserChange()
    userId = "new-user"
    service.getOverride = nil
    await store.refresh()
    reply?.resume(returning: CalendarSubscriptionState(metadata: makeMetadata()))
    await oldRefresh.value
    XCTAssertFalse(store.isActive)
    XCTAssertTrue(store.canOfferSetup)

    service.getError = URLError(.notConnectedToInternet)
    let nextLaunch = makeStore(service: service, defaults: defaults, userId: "new-user")
    await nextLaunch.refresh()
    XCTAssertFalse(nextLaunch.isActive)
    XCTAssertTrue(nextLaunch.canOfferSetup)
  }

  func testOldAccountsRotationCannotSaveOrOpenAFeedForTheNewAccount() async throws {
    let service = MockCalendarSubscriptionService(
      state: .inactive, activeAfterDuplicate: .inactive, createError: nil
    )
    let started = expectation(description: "Old account rotation started")
    var reply: CheckedContinuation<CalendarSubscriptionCreated, Error>?
    service.createOverride = {
      try await withCheckedThrowingContinuation {
        reply = $0
        started.fulfill()
      }
    }
    var userId = "old-user"
    let tokens = InMemoryCalendarSubscriptionTokenStore()
    let store = CalendarSubscriptionStore(
      service: service, tokenStore: tokens, defaults: makeDefaults(), userIdProvider: { userId }
    )
    // Match the settings action, which opens the feed only after the rotation returns.
    let rotation = Task {
      _ = try await store.rotate(mode: nil)
      return try await store.rawTokenForActiveSubscription()
    }
    await fulfillment(of: [started], timeout: 2)
    store.resetForUserChange()
    userId = "new-user"
    await store.refresh()
    let oldMetadata = makeMetadata(id: "old-subscription")
    reply?.resume(
      returning: CalendarSubscriptionCreated(metadata: oldMetadata, rawToken: "old-secret"))
    do {
      _ = try await rotation.value
      XCTFail("A stale rotation must stop the settings action")
    } catch is CancellationError {
      // The caller cannot proceed to open the old feed.
    }
    XCTAssertNil(tokens.loadToken(userId: "new-user", metadata: oldMetadata))
    XCTAssertNil(tokens.loadToken(userId: "old-user", metadata: oldMetadata))
    XCTAssertNil(store.activeMetadata)
    XCTAssertNil(store.errorMessage)
    XCTAssertTrue(store.canOfferSetup)
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
      string: "https://api.tidex.no/functions/v1/calendar-feed/old.ics")

    try await store.disable()

    XCTAssertNil(store.fallbackHTTPSURL)
  }

  func testRefreshOfflineKeepsLastKnownSubscription() async {
    let defaults = makeDefaults()
    let metadata = makeMetadata()
    let online = MockCalendarSubscriptionService(
      state: CalendarSubscriptionState(metadata: metadata),
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    let firstLaunch = makeStore(service: online, defaults: defaults)
    await firstLaunch.refresh()

    let offline = MockCalendarSubscriptionService(
      state: .inactive,
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    offline.getError = URLError(.notConnectedToInternet)
    let secondLaunch = makeStore(service: offline, defaults: defaults)
    await secondLaunch.refresh()

    XCTAssertEqual(secondLaunch.state.metadata, metadata)
    XCTAssertFalse(secondLaunch.isStateUnknown)
    XCTAssertFalse(secondLaunch.canOfferSetup)
    XCTAssertEqual(secondLaunch.errorMessage, ErrorTranslations.offlineMessage)
  }

  func testRefreshOfflineWithoutStoredStateIsUnknownNotInactive() async {
    let offline = MockCalendarSubscriptionService(
      state: .inactive,
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    offline.getError = URLError(.notConnectedToInternet)
    let store = makeStore(service: offline, defaults: makeDefaults())

    await store.refresh()

    XCTAssertTrue(store.isStateUnknown)
    XCTAssertFalse(store.canOfferSetup)
    XCTAssertEqual(store.errorMessage, ErrorTranslations.offlineMessage)

    // A later successful refresh replaces the unknown state.
    offline.getError = nil
    await store.refresh()

    XCTAssertFalse(store.isStateUnknown)
    XCTAssertTrue(store.canOfferSetup)
  }

  func testRefreshOfflineAfterInactiveResultStaysInactive() async {
    let defaults = makeDefaults()
    let online = MockCalendarSubscriptionService(
      state: .inactive,
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    await makeStore(service: online, defaults: defaults).refresh()

    let offline = MockCalendarSubscriptionService(
      state: .inactive,
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    offline.getError = URLError(.notConnectedToInternet)
    let store = makeStore(service: offline, defaults: defaults)
    await store.refresh()

    XCTAssertFalse(store.isStateUnknown)
    XCTAssertTrue(store.canOfferSetup)
  }

  func testStoredStateFromAnotherUserIsIgnored() async {
    let defaults = makeDefaults()
    let online = MockCalendarSubscriptionService(
      state: CalendarSubscriptionState(metadata: makeMetadata()),
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    await makeStore(service: online, defaults: defaults, userId: "user-1").refresh()

    let offline = MockCalendarSubscriptionService(
      state: .inactive,
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    offline.getError = URLError(.notConnectedToInternet)
    let store = makeStore(service: offline, defaults: defaults, userId: "user-2")
    await store.refresh()

    XCTAssertNil(store.state.metadata)
    XCTAssertTrue(store.isStateUnknown)
  }

  func testResetForUserChangeClearsStoredState() async {
    let defaults = makeDefaults()
    let online = MockCalendarSubscriptionService(
      state: CalendarSubscriptionState(metadata: makeMetadata()),
      activeAfterDuplicate: .inactive,
      createError: nil
    )
    let store = makeStore(service: online, defaults: defaults)
    await store.refresh()

    store.resetForUserChange()
    online.getError = URLError(.notConnectedToInternet)
    await store.refresh()

    XCTAssertNil(store.state.metadata)
    XCTAssertTrue(store.isStateUnknown)
  }

}

extension CalendarSubscriptionStoreTests {
  func testVerifiedAccountChangeClearsThePreviousSubscriptionAndFallbackURL() async {
    let service = MockCalendarSubscriptionService(
      state: CalendarSubscriptionState(metadata: makeMetadata()),
      activeAfterDuplicate: .inactive, createError: nil)
    var userId = "target"
    let store = CalendarSubscriptionStore(
      service: service, tokenStore: InMemoryCalendarSubscriptionTokenStore(),
      defaults: makeDefaults(), userIdProvider: { userId })
    await store.refresh()
    store.fallbackHTTPSURL = URL(string: "https://example.com/private-target-calendar.ics")

    userId = "administrator"
    store.prepareForUser(userId, replacing: "target")
    XCTAssertNil(store.activeMetadata)
    XCTAssertNil(store.fallbackHTTPSURL)
    service.getOverride = { .inactive }
    await store.refreshIfNeeded()
    XCTAssertFalse(store.isActive)
    XCTAssertTrue(store.canOfferSetup)
  }

  func testOfflineLaunchCannotRestoreAnotherAccountsStoredSubscription() async {
    let defaults = makeDefaults()
    let online = MockCalendarSubscriptionService(
      state: CalendarSubscriptionState(metadata: makeMetadata()),
      activeAfterDuplicate: .inactive, createError: nil)
    await makeStore(service: online, defaults: defaults, userId: "target").refresh()
    let offline = MockCalendarSubscriptionService(
      state: .inactive, activeAfterDuplicate: .inactive, createError: nil)
    offline.getError = URLError(.notConnectedToInternet)
    let store = CalendarSubscriptionStore(
      service: offline, tokenStore: InMemoryCalendarSubscriptionTokenStore(), defaults: defaults,
      userIdProvider: { throw URLError(.notConnectedToInternet) })
    store.prepareForUser("administrator", replacing: nil)
    await store.refresh()

    XCTAssertNil(store.activeMetadata)
    XCTAssertTrue(store.isStateUnknown)
  }

  func testPreparingTheSameAccountKeepsItsOfflineSubscriptionState() async {
    let service = MockCalendarSubscriptionService(
      state: CalendarSubscriptionState(metadata: makeMetadata()),
      activeAfterDuplicate: .inactive, createError: nil)
    let store = makeStore(service: service, defaults: makeDefaults())
    await store.refresh()
    store.prepareForUser("user-1", replacing: nil)
    service.getError = URLError(.notConnectedToInternet)
    await store.refreshIfNeeded()

    XCTAssertTrue(store.isActive)
    XCTAssertFalse(store.isStateUnknown)
  }

  fileprivate func makeDefaults() -> UserDefaults {
    let suiteName = "CalendarSubscriptionStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  fileprivate func makeStore(
    service: CalendarSubscriptionServicing,
    defaults: UserDefaults,
    userId: String = "user-1"
  ) -> CalendarSubscriptionStore {
    CalendarSubscriptionStore(
      service: service,
      tokenStore: InMemoryCalendarSubscriptionTokenStore(),
      defaults: defaults,
      userIdProvider: { userId }
    )
  }

  fileprivate func makeMetadata(
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

// `@unchecked` is safe because only the main actor tests touch the mock.
private final class MockCalendarSubscriptionService: CalendarSubscriptionServicing,
  @unchecked Sendable
{
  var state: CalendarSubscriptionState
  let activeAfterDuplicate: CalendarSubscriptionState
  let createError: Error?
  var createOverride: (@MainActor @Sendable () async throws -> CalendarSubscriptionCreated)?
  var getError: Error?
  var getOverride: (@MainActor @Sendable () async throws -> CalendarSubscriptionState)?

  init(
    state: CalendarSubscriptionState,
    activeAfterDuplicate: CalendarSubscriptionState,
    createError: Error?
  ) {
    self.state = state
    self.activeAfterDuplicate = activeAfterDuplicate
    self.createError = createError
  }

  func getSubscription() async throws -> CalendarSubscriptionState {
    if let getOverride { return try await getOverride() }
    if let getError {
      throw getError
    }
    if createError != nil {
      state = activeAfterDuplicate
    }
    return state
  }

  func createSubscription(mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionCreated
  {
    if let createOverride { return try await createOverride() }
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
    URL(string: "webcal://api.tidex.no/functions/v1/calendar-feed/\(rawToken).ics")
  }

  func httpsURL(rawToken: String) -> URL? {
    URL(string: "https://api.tidex.no/functions/v1/calendar-feed/\(rawToken).ics")
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
