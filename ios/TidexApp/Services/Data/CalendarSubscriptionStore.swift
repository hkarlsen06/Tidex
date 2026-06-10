import Combine
import Foundation
import os.log
import UIKit

private let calendarSubscriptionStoreLogger = Logger(
  subsystem: "com.tidex.app",
  category: "CalendarSubscriptionStore"
)

@MainActor
final class CalendarSubscriptionStore: ObservableObject {
  static let shared = CalendarSubscriptionStore()

  @Published private(set) var state: CalendarSubscriptionState = .inactive
  @Published private(set) var isLoading = false
  @Published private(set) var isMutating = false
  @Published var errorMessage: String?
  @Published var fallbackHTTPSURL: URL?

  private let service: CalendarSubscriptionServicing
  private let tokenStore: CalendarSubscriptionTokenStoring
  private let userIdProvider: () async throws -> String
  private var hasLoadedForCurrentSession = false

  init(
    service: CalendarSubscriptionServicing = CalendarSubscriptionService.shared,
    tokenStore: CalendarSubscriptionTokenStoring = CalendarSubscriptionKeychainStore.shared,
    userIdProvider: @escaping () async throws -> String = {
      try await AuthSessionManager.shared.getUserId()
    }
  ) {
    self.service = service
    self.tokenStore = tokenStore
    self.userIdProvider = userIdProvider
  }

  var isActive: Bool {
    state.isActive
  }

  var activeMetadata: CalendarSubscriptionMetadata? {
    state.metadata
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
      hasLoadedForCurrentSession = true
    } catch {
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
      return created
    }
  }

  func setContentMode(_ mode: CalendarSubscriptionContentMode) async throws {
    try await mutate {
      let metadata = try await service.setContentMode(mode)
      state = CalendarSubscriptionState(metadata: metadata)
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
    isLoading = false
    isMutating = false
    errorMessage = nil
    fallbackHTTPSURL = nil
    hasLoadedForCurrentSession = false
  }

  static func clearStoredTokensForUserReset() {
    CalendarSubscriptionKeychainStore.shared.clearAllTokens()
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
