import ConvexMobile
import SwiftUI

extension View {
  /// Runs `reload` each time the result of a Convex query changes while the view is on screen,
  /// and once more when the first result arrives after (re)subscribing. The screen keeps loading
  /// over HTTP, and this tells it when to load again, so a change made elsewhere shows up
  /// within a second. The reloads are quiet: every screen that uses this keeps its rows while it
  /// loads again. A new `id` restarts the watch, for screens whose
  /// arguments change. If the connection drops, it tries again every 10 seconds.
  func reloadOnChange(
    of query: String,
    args: [String: ConvexEncodable?] = [:],
    id: some Equatable = 0,
    perform reload: @escaping @MainActor () async -> Void
  ) -> some View {
    task(id: id) {
      while !Task.isCancelled {
        for await _ in await ConvexRealtime.shared.changes(of: query, args: args) {
          await reload()
        }
        try? await Task.sleep(for: .seconds(10))
      }
    }
  }
}
