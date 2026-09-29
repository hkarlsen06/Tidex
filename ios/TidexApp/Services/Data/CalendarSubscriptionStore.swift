import Foundation
import Observation
import os.log
import UIKit

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
  private(set) var isStateUnknown = false
  var errorMessage: String?
  var fallbackHTTPSURL: URL?

  private let service: CalendarSubscriptionServicing
  private let tokenStore: CalendarSubscriptionTokenStoring
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let userIdProvider: () async throws -> String
  @ObservationIgnored private var hasLoadedForCurrentSession = false

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
    isLoading = true
    errorMessage = nil
    fallbackHTTPSURL = nil
    defer { isLoading = false }

    do {
      state = try await service.getSubscription()
      isStateUnknown = false
      hasLoadedForCurrentSession = true
      await remember(state)
    } catch {
      // Keep what the screen already shows. Otherwise fall back to the last known state.
      if !hasLoadedForCurrentSession {
        if let lastKnown = await lastKnownState() {
          state = lastKnown
          isStateUnknown = false
        } else {
          isStateUnknown = true
        }
      }
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  @discardableResult
  func create(mode: CalendarSubscriptionContentMode) async throws -> CalendarSubscriptionCreated {
    try await mutate {
      do {
        let created = try await service.createSubscription(mode: mode)
        try await save(created: created)
        state = CalendarSubscriptionState(metadata: created.metadata)
        await remember(state)
        return created
      } catch  where CalendarSubscriptionService.isDuplicateActiveSubscriptionError(error) {
        state = try await service.getSubscription()
        throw CalendarSubscriptionStoreError.subscriptionAlreadyActive
      }
    }
  }

  @discardableResult
  func rotate(mode: CalendarSubscriptionContentMode?) async throws -> CalendarSubscriptionCreated {
    try await mutate {
      let created = try await service.rotateSubscription(mode: mode)
      try await save(created: created)
      state = CalendarSubscriptionState(metadata: created.metadata)
      await remember(state)
      return created
    }
  }

  func setContentMode(_ mode: CalendarSubscriptionContentMode) async throws {
    try await mutate {
      let metadata = try await service.setContentMode(mode)
      state = CalendarSubscriptionState(metadata: metadata)
      await remember(state)
      return ()
    }
  }

  func disable() async throws {
    try await mutate {
      let previousMetadata = state.metadata
      let disabled = try await service.disableSubscription()
      if disabled, let previousMetadata {
        let userId = try await userIdProvider()
        tokenStore.deleteToken(userId: userId, metadata: previousMetadata)
      }
      state = .inactive
      await remember(state)
      fallbackHTTPSURL = nil
      return ()
    }
  }

  func openCalendarApp() async {
    do {
      fallbackHTTPSURL = nil
      let rawToken = try await rawTokenForActiveSubscription()
      guard let webcalURL = service.webcalURL(rawToken: rawToken) else {
        throw CalendarSubscriptionStoreError.invalidURL
      }

      let opened = await UIApplication.shared.open(webcalURL)
      if !opened, let httpsURL = service.httpsURL(rawToken: rawToken) {
        fallbackHTTPSURL = httpsURL
        errorMessage = String(localized: .calendarSubscriptionOpenFallbackMessage)
      }
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  func copyFallbackURL() {
    guard let fallbackHTTPSURL else { return }
    UIPasteboard.general.string = fallbackHTTPSURL.absoluteString
  }

  func rawTokenForActiveSubscription() async throws -> String {
    guard let metadata = state.metadata else {
      throw CalendarSubscriptionStoreError.noActiveSubscription
    }

    let userId = try await userIdProvider()
    guard let token = tokenStore.loadToken(userId: userId, metadata: metadata) else {
      throw CalendarSubscriptionStoreError.missingLocalToken
    }

    return token.rawToken
  }

  func resetForUserChange() {
    state = .inactive
    isStateUnknown = false
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

  private func remember(_ state: CalendarSubscriptionState) async {
    guard let userId = try? await userIdProvider(),
      let data = try? JSONEncoder().encode(LastKnownState(userId: userId, metadata: state.metadata))
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

  private func save(created: CalendarSubscriptionCreated) async throws {
    let userId = try await userIdProvider()
    try tokenStore.saveToken(
      CalendarSubscriptionKeychainToken(
        userId: userId,
        subscriptionId: created.metadata.id,
        tokenSuffix: created.metadata.tokenSuffix,
        rawToken: created.rawToken
      ))
  }

  private func mutate<T>(_ operation: () async throws -> T) async throws -> T {
    guard !isMutating else { throw CalendarSubscriptionStoreError.operationInProgress }
    isMutating = true
    errorMessage = nil
    defer { isMutating = false }

    do {
      return try await operation()
    } catch {
      if !(error is CalendarSubscriptionStoreError) {
        calendarSubscriptionStoreLogger.warning(
          "Calendar subscription mutation failed: \(error.localizedDescription)")
      }
      errorMessage = ErrorTranslations.translate(error)
      throw error
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
