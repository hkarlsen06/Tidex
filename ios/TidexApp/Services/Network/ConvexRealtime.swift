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

  // ConvexMobile's client is not Sendable and its login is an async method, so the compiler
  // would reject passing it out of the main actor. Only this class touches it.
  private nonisolated(unsafe) var client: ConvexClientWithAuth<String>?
  /// Clients of earlier sign-ins. Freeing one panics in the Rust library when its last
  /// reference goes away on one of the library's own threads, which happens after a sign-out,
  /// so they stay alive.
  /// ponytail: keeps one idle client per sign-out until the app quits. Reuse one client if
  /// people start switching accounts often.
  private nonisolated(unsafe) var retiredClients: [ConvexClientWithAuth<String>] = []
  private var isSignedIn = false
  private var signInTask: Task<Bool, Never>?
  /// Bumped by every sign-out. A login that finishes after one belongs to the old account.
  private var generation = 0

  /// Whether the client's WebSocket is connected. The client reconnects by itself after it loses
  /// the server, and a reconnect asks AppCoordinator to retry a failed sync.
  private var isConnected = false
  private var connectionStateSubscription: AnyCancellable?
  private var reconnectTask: Task<Void, Never>?
  /// The socket can drop again right after it connects, so wait this long before retrying.
  private static let reconnectDebounce: Duration = .seconds(1.5)

  private init() {}

  /// Signs the client in with the current Clerk session. Returns false when nobody is signed
  /// in or the server refused the token. Safe to call again while signed in.
  func signIn() async -> Bool {
    if isSignedIn { return true }
    // Unit tests run coordinators with fake services and have no Clerk session to sign in with.
    if NSClassFromString("XCTestCase") != nil { return false }
    if let signInTask { return await signInTask.value }

    let started = generation
    let task = Task { @MainActor [self] in
      nonisolated(unsafe) let client = makeClient()
      switch await client.login() {
      case .success:
        // Signed out while the login ran, so its token may be the previous account's.
        guard generation == started else {
          retiredClients.append(client)
          await client.logout()
          return false
        }
        isSignedIn = true
        return true

      case .failure(let error):
        logger.error("Convex sign-in failed: \(error.localizedDescription)")
        return false
      }
    }
    signInTask = task
    let signedIn = await task.value
    if generation == started { signInTask = nil }
    return signedIn
  }

  /// Ends the session of the client. Cancel the subscriptions first. The next sign-in gets a
  /// new client and token provider, so nothing from this account carries over.
  func signOut() async {
    generation += 1
    signInTask = nil
    isSignedIn = false
    connectionStateSubscription = nil
    reconnectTask?.cancel()
    reconnectTask = nil
    isConnected = false
    guard let current = client else { return }
    self.client = nil
    retiredClients.append(current)
    // logout runs off the main actor. The client is retired, so nothing here uses it meanwhile.
    nonisolated(unsafe) let retired = current
    await retired.logout()
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

  /// Yields once for each result of a query, the first one included, for screens that load
  /// over HTTP and only need to know when to load again. The first result matters too: the
  /// screen's own load may have failed offline, or the data may have changed before the
  /// subscription started. Finishes when the subscription fails or nobody is signed in, and
  /// stops the subscription when the caller stops listening.
  func changes(of name: String, args: [String: ConvexEncodable?] = [:]) async -> AsyncStream<Void> {
    guard await signIn() else { return AsyncStream { $0.finish() } }
    return AsyncStream { continuation in
      let subscription = subscribe(
        to: name, args: args, as: ConvexAPI.Ignored.self,
        onUpdate: { _ in continuation.yield() },
        onFailure: { _ in continuation.finish() }
      )
      guard let subscription else {
        continuation.finish()
        return
      }
      nonisolated(unsafe) let held = subscription
      continuation.onTermination = { _ in held.cancel() }
    }
  }

  private func makeClient() -> ConvexClientWithAuth<String> {
    if let client { return client }
    let created = ConvexClientWithAuth<String>(
      deploymentUrl: ConvexAPI.appDeploymentURL.absoluteString,
      authProvider: ClerkConvexAuthProvider()
    )
    client = created
    connectionStateSubscription = created.watchWebSocketState()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        MainActor.assumeIsolated { self?.handle(state) }
      }
    return created
  }

  private func handle(_ state: WebSocketState) {
    let transition = ConnectivityTransition.between(
      wasOnline: isConnected, isOnline: state == .connected)
    isConnected = state == .connected
    switch transition {
    case .none:
      break
    case .wentOffline:
      reconnectTask?.cancel()
    case .wentOnline:
      reconnectTask?.cancel()
      reconnectTask = Task { [weak self] in
        try? await Task.sleep(for: Self.reconnectDebounce)
        guard !Task.isCancelled, self?.isConnected == true else { return }
        await AppCoordinator.shared.handleServerReconnected()
      }
    }
  }
}
