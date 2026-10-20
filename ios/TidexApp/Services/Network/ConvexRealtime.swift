import Combine
import ConvexMobile
import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "ConvexRealtime")

/// Gives the Convex client Clerk tokens. A token lasts about 60 seconds, so a task pushes a
/// fresh one every 45 seconds while the client is signed in. The client also asks for a fresh
/// one through `loginFromCache` when the server refuses the current one.
actor ClerkConvexAuthProvider: AuthProvider {
  // swiftlint:disable:next type_name
  typealias T = String

  private static let refreshInterval: Duration = .seconds(45)

  private var refreshTask: Task<Void, Never>?

  func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
    try await begin(onIdToken)
  }

  func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
    try await begin(onIdToken)
  }

  // swiftlint:disable:next async_without_await
  func logout() async throws {
    refreshTask?.cancel()
    refreshTask = nil
  }

  nonisolated func extractIdToken(from authResult: String) -> String {
    authResult
  }

  private func begin(_ onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
    guard let token = try await AuthSessionManager.shared.convexToken(forceRefresh: true) else {
      throw AuthSessionManagerError.notSignedIn
    }
    refreshTask?.cancel()
    refreshTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.refreshInterval)
        guard !Task.isCancelled else { return }
        do {
          // A nil token tells the client that the session ended.
          onIdToken(try await AuthSessionManager.shared.convexToken(forceRefresh: true))
        } catch {
          logger.warning("Convex token refresh failed: \(error.localizedDescription)")
        }
      }
    }
    return token
  }
}

/// The Convex WebSocket client. Chat subscriptions use it, so the screens update when the
/// data changes. Calls that read or write once go through `ConvexAPI` over HTTP.
@MainActor
final class ConvexRealtime {
  static let shared = ConvexRealtime()

  private let authProvider = ClerkConvexAuthProvider()
  // ConvexMobile's client is not Sendable and its login is an async method, so the compiler
  // would reject passing it out of the main actor. Only this class touches it.
  private nonisolated(unsafe) var client: ConvexClientWithAuth<String>?
  private var isSignedIn = false
  private var signInTask: Task<Bool, Never>?

  private init() {}

  /// Signs the client in with the current Clerk session. Returns false when nobody is signed
  /// in or the server refused the token. Safe to call again while signed in.
  func signIn() async -> Bool {
    if isSignedIn { return true }
    if let signInTask { return await signInTask.value }

    let task = Task { @MainActor [self] in
      nonisolated(unsafe) let client = makeClient()
      switch await client.login() {
      case .success:
        isSignedIn = true
        return true

      case .failure(let error):
        logger.error("Convex sign-in failed: \(error.localizedDescription)")
        return false
      }
    }
    signInTask = task
    let signedIn = await task.value
    signInTask = nil
    return signedIn
  }

  /// Ends the session of the client. Cancel the subscriptions first.
  func signOut() async {
    signInTask?.cancel()
    signInTask = nil
    guard isSignedIn, client != nil else { return }
    isSignedIn = false
    nonisolated(unsafe) let client = client
    await client?.logout()
  }

  /// Subscribes to a query. `onUpdate` runs on the main actor with each new result, the first
  /// one included. After `onFailure` runs the subscription has ended, so the caller subscribes
  /// again if it still wants the data. Cancel the returned object to unsubscribe. Pass numbers
  /// as `Double`, because the client sends an `Int` as an int64 that `v.number()` rejects.
  func subscribe<Value: Decodable>(
    to name: String,
    args: [String: ConvexEncodable?] = [:],
    as _: Value.Type = Value.self,
    onUpdate: @escaping @MainActor (Value) -> Void,
    onFailure: @escaping @MainActor (Error) -> Void
  ) -> AnyCancellable? {
    guard isSignedIn, let client else { return nil }
    return client.subscribe(to: name, with: args, yielding: Value.self)
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
            MainActor.assumeIsolated { onFailure(error) }
          }
        },
        receiveValue: { value in
          MainActor.assumeIsolated { onUpdate(value) }
        }
      )
  }

  private func makeClient() -> ConvexClientWithAuth<String> {
    if let client { return client }
    let created = ConvexClientWithAuth<String>(
      deploymentUrl: ConvexAPI.appDeploymentURL.absoluteString,
      authProvider: authProvider
    )
    client = created
    return created
  }
}
