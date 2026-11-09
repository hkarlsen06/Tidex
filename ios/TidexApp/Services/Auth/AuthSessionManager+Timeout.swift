import Foundation

extension AuthSessionManager {
  func withTimeout<T: Sendable>(
    timeout: Duration = .seconds(20),
    _ operation: @escaping @MainActor @Sendable () async throws -> T
  ) async throws -> T {
    // Clerk and the shared user lookup await unstructured tasks. Cancelling a task
    // group cannot end those waits, and leaving the group waits for every child.
    let results = AsyncThrowingStream<T, Error>(bufferingPolicy: .bufferingNewest(1)) {
      continuation in
      let work = Task {
        do {
          try Task.checkCancellation()
          let value = try await operation()
          try Task.checkCancellation()
          continuation.yield(value)
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      let timer = Task {
        do {
          try await Task.sleep(for: timeout)
          continuation.finish(throwing: AuthSessionManagerError.sessionFetchTimedOut)
        } catch { /* The operation finished or its caller cancelled. */  }
      }
      continuation.onTermination = { _ in
        work.cancel()
        timer.cancel()
      }
    }
    var iterator = results.makeAsyncIterator()
    guard let value = try await iterator.next() else { throw CancellationError() }
    try Task.checkCancellation()
    return value
  }
}
