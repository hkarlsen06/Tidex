import Foundation
import Observation
import UIKit
import os.log

private let calendarSubscriptionStoreLogger = Logger(
  subsystem: "com.tidex.app",
  category: "CalendarSubscriptionStore"
)

@MainActor
@Observable
final class CalendarSubscriptionStore {
  static let shared = CalendarSubscriptionStore()

  private(set) var state: CalendarSubscriptionState = .inactive
  private(set) var isLoading = false
  private(set) var isMutating = false
  /// True when the last refresh failed and no earlier result is stored, so the app can't
  /// tell whether a subscription exists. Screens must not offer "Set up" in this state.
  private(set) var isStateUnknown = true
  var errorMessage: String?
  var fallbackHTTPSURL: URL?

  private let service: CalendarSubscriptionServicing
  private let tokenStore: CalendarSubscriptionTokenStoring
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let userIdProvider: () async throws -> String
  @ObservationIgnored private var hasLoadedForCurrentSession = false
  @ObservationIgnored private var userGeneration = 0

  init(
    service: CalendarSubscriptionServicing = CalendarSubscriptionService.shared,
    tokenStore: CalendarSubscriptionTokenStoring = CalendarSubscriptionKeychainStore.shared,
    defaults: UserDefaults = .standard,
    userIdProvider: @escaping () async throws -> String = {
      try await AuthSessionManager.shared.getUserId()
    }
  ) {
    self.service = service
    self.tokenStore = tokenStore
    self.defaults = defaults
    self.userIdProvider = userIdProvider
  }

  var isActive: Bool {
    state.isActive
  }

  var activeMetadata: CalendarSubscriptionMetadata? {
    state.metadata
  }

  /// Whether the "set up calendar subscription" prompt is accurate right now.
  var canOfferSetup: Bool {
    !isActive && !isStateUnknown
  }

  func refreshIfNeeded() async {
    guard !hasLoadedForCurrentSession else { return }
    await refresh()
  }

  func refresh() async {
    guard !isLoading else { return }
    let generation = userGeneration
    isLoading = true
    errorMessage = nil
    fallbackHTTPSURL = nil
    defer {
      if generation == userGeneration { isLoading = false }
    }

    do {
      let userId = try await userIdProvider()
      guard generation == userGeneration, !Task.isCancelled else { return }
      let refreshedState = try await service.getSubscription()
      guard generation == userGeneration, !Task.isCancelled else { return }
      state = refreshedState
      isStateUnknown = false
      hasLoadedForCurrentSession = true
      remember(state, userId: userId)
    } catch {
      guard generation == userGeneration, !Task.isCancelled else { return }
      // Keep what the screen already shows. Otherwise fall back to the last known state.
      if !hasLoadedForCurrentSession {
        let lastKnown = await lastKnownState()
        guard generation == userGeneration, !Task.isCancelled else { return }
        state = lastKnown ?? state
        isStateUnknown = lastKnown == nil
      }
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  @discardableResult
  func create(mode: CalendarSubscriptionContentMode) async throws -> CalendarSubscriptionCreated {
    try await mutate { account in
      do {
        let created = try await service.createSubscription(mode: mode)
        try save(created: created, account: account)
        state = CalendarSubscriptionState(metadata: created.metadata)
        remember(state, userId: account.userId)
        return created
      } catch  where CalendarSubscriptionService.isDuplicateActiveSubscriptionError(error) {
        let refreshed = try await service.getSubscription()
        try validate(account)
        state = refreshed
        remember(state, userId: account.userId)
        throw CalendarSubscriptionStoreError.subscriptionAlreadyActive
      }
    }
  }

  @discardableResult
  func rotate(mode: CalendarSubscriptionContentMode?) async throws -> CalendarSubscriptionCreated {
    try await mutate { account in
      let created = try await service.rotateSubscription(mode: mode)
      try save(created: created, account: account)
      state = CalendarSubscriptionState(metadata: created.metadata)
      remember(state, userId: account.userId)
      return created
    }
  }

  func setContentMode(_ mode: CalendarSubscriptionContentMode) async throws {
    try await mutate { account in
      let metadata = try await service.setContentMode(mode)
      try validate(account)
      state = CalendarSubscriptionState(metadata: metadata)
      remember(state, userId: account.userId)
      return ()
    }
  }

  func disable() async throws {
    try await mutate { account in
      let previousMetadata = state.metadata
      let disabled = try await service.disableSubscription()
      try validate(account)
      if disabled, let previousMetadata {
        tokenStore.deleteToken(userId: account.userId, metadata: previousMetadata)
      }
      state = .inactive
      remember(state, userId: account.userId)
      fallbackHTTPSURL = nil
      return ()
    }
  }

  func openCalendarApp() async {
    let generation = userGeneration
    let metadata = state.metadata
    do {
      fallbackHTTPSURL = nil
      let rawToken = try await rawTokenForActiveSubscription()
      guard generation == userGeneration, metadata == state.metadata, !Task.isCancelled else {
        return
      }
      guard let webcalURL = service.webcalURL(rawToken: rawToken) else {
        throw CalendarSubscriptionStoreError.invalidURL
      }

      let opened = await UIApplication.shared.open(webcalURL)
      guard generation == userGeneration, metadata == state.metadata, !Task.isCancelled else {
        return
      }
      if !opened, let httpsURL = service.httpsURL(rawToken: rawToken) {
        fallbackHTTPSURL = httpsURL
        errorMessage = String(localized: .calendarSubscriptionOpenFallbackMessage)
      }
    } catch {
      guard generation == userGeneration, !Task.isCancelled else { return }
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  func copyFallbackURL() {
    guard let fallbackHTTPSURL else { return }
    UIPasteboard.general.string = fallbackHTTPSURL.absoluteString
  }

  func rawTokenForActiveSubscription() async throws -> String {
    let generation = userGeneration
    guard let metadata = state.metadata else {
      throw CalendarSubscriptionStoreError.noActiveSubscription
    }

    let userId = try await userIdProvider()
    guard generation == userGeneration, metadata == state.metadata, !Task.isCancelled else {
      throw CancellationError()
    }
    guard let token = tokenStore.loadToken(userId: userId, metadata: metadata) else {
      throw CalendarSubscriptionStoreError.missingLocalToken
    }

    return token.rawToken
  }

  func resetForUserChange() {
    userGeneration += 1
    state = .inactive
    isStateUnknown = true
    defaults.removeObject(forKey: Self.lastKnownStateKey)
    isLoading = false
    isMutating = false
    errorMessage = nil
    fallbackHTTPSURL = nil
    hasLoadedForCurrentSession = false
  }

  static func clearStoredTokensForUserReset() {
    CalendarSubscriptionKeychainStore.shared.clearAllTokens()
  }

  private static let lastKnownStateKey = "calendar_subscription_last_known_state"

  /// Metadata holds no secret (the raw token lives in the keychain), so UserDefaults is fine.
  private struct LastKnownState: Codable {
    let userId: String
    let metadata: CalendarSubscriptionMetadata?
  }

  private func remember(_ state: CalendarSubscriptionState, userId: String) {
    guard
      let data = try? JSONEncoder().encode(
        LastKnownState(userId: userId, metadata: state.metadata))
    else { return }
    defaults.set(data, forKey: Self.lastKnownStateKey)
  }

  /// The stored state, unless it belongs to another user. When the user id can't be
  /// resolved offline, the entry is trusted because sign-out and user change clear it.
  private func lastKnownState() async -> CalendarSubscriptionState? {
    guard let data = defaults.data(forKey: Self.lastKnownStateKey),
      let stored = try? JSONDecoder().decode(LastKnownState.self, from: data)
    else { return nil }

    if let userId = try? await userIdProvider(), userId != stored.userId {
      return nil
    }
    return CalendarSubscriptionState(metadata: stored.metadata)
  }

  private struct AccountContext {
    let userId: String
    let generation: Int
  }

  private func validate(_ account: AccountContext) throws {
    guard account.generation == userGeneration, !Task.isCancelled else {
      throw CancellationError()
    }
  }

  private func save(created: CalendarSubscriptionCreated, account: AccountContext) throws {
    try validate(account)
    try tokenStore.saveToken(
      CalendarSubscriptionKeychainToken(
        userId: account.userId,
        subscriptionId: created.metadata.id,
        tokenSuffix: created.metadata.tokenSuffix,
        rawToken: created.rawToken
      ))
  }

  private func mutate<T>(_ operation: (AccountContext) async throws -> T) async throws -> T {
    guard !isMutating else { throw CalendarSubscriptionStoreError.operationInProgress }
    let generation = userGeneration
    isMutating = true
    errorMessage = nil
    defer {
      if generation == userGeneration { isMutating = false }
    }

    do {
      let account = AccountContext(userId: try await userIdProvider(), generation: generation)
      try validate(account)
      let result = try await operation(account)
      try validate(account)
      isStateUnknown = false
      hasLoadedForCurrentSession = true
      return result
    } catch {
      guard generation == userGeneration, !Task.isCancelled, !(error is CancellationError) else {
        throw CancellationError()
      }
      if !(error is CalendarSubscriptionStoreError) {
        calendarSubscriptionStoreLogger.warning(
          "Calendar subscription mutation failed: \(error.localizedDescription)")
      }
      errorMessage = ErrorTranslations.translate(error)
      throw error
    }
  }
}

extension CalendarSubscriptionStore {
  func prepareForUser(_ userId: String, replacing previousUserId: String?) {
    let stored = defaults.data(forKey: Self.lastKnownStateKey).flatMap {
      try? JSONDecoder().decode(LastKnownState.self, from: $0)
    }
    if let previousUserId, previousUserId != userId {
      resetForUserChange()
    } else if let stored, stored.userId != userId {
      resetForUserChange()
    }
  }
}

enum CalendarSubscriptionStoreError: Error, LocalizedError, Equatable {
  case operationInProgress
  case noActiveSubscription
  case missingLocalToken
  case invalidURL
  case subscriptionAlreadyActive

  var errorDescription: String? {
    switch self {
    case .operationInProgress:
      return String(localized: .calendarSubscriptionErrorOperationInProgress)

    case .noActiveSubscription:
      return String(localized: .calendarSubscriptionErrorNoActive)

    case .missingLocalToken:
      return String(localized: .calendarSubscriptionErrorMissingToken)

    case .invalidURL:
      return String(localized: .calendarSubscriptionErrorInvalidUrl)

    case .subscriptionAlreadyActive:
      return String(localized: .calendarSubscriptionErrorAlreadyActive)
    }
  }
}
