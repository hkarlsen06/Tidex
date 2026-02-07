import SwiftUI

// MARK: - Pull to Refresh Configuration

/// Kept for API compatibility with existing call sites.
struct PullToRefreshConfig {
  static let `default` = PullToRefreshConfig()
}

// MARK: - Pull to Refresh Container

/// A thin native `.refreshable` wrapper for non-scrollable content.
/// For already-scrollable views, apply `.refreshable` directly on the ScrollView/List instead.
struct PullToRefreshContainer<Content: View>: View {

  // MARK: - Properties

  let onRefresh: () async -> Void
  let config: PullToRefreshConfig
  @ViewBuilder let content: () -> Content

  // MARK: - Initialization

  init(
    config: PullToRefreshConfig = .default,
    onRefresh: @escaping () async -> Void,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.config = config
    self.onRefresh = onRefresh
    self.content = content
  }

  // MARK: - Body

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        content()
          .frame(maxWidth: .infinity, alignment: .top)
          // +1 ensures the host is treated as scrollable, so `.refreshable` can trigger
          // even when the visible content would otherwise exactly match viewport height.
          .frame(minHeight: geometry.size.height + 1, alignment: .top)
      }
      // Required for non-scrollable/fixed-height surfaces so pull-to-refresh can arm.
      .scrollBounceBehavior(.always, axes: .vertical)
      .refreshable {
        await onRefresh()
      }
      .scrollIndicators(.hidden)
    }
  }
}

// MARK: - View Extension

extension View {
  /// Adds pull-to-refresh functionality to non-scrollable content.
  /// For scrollable content, prefer applying `.refreshable` directly.
  func pullToRefresh(
    config: PullToRefreshConfig = .default,
    onRefresh: @escaping () async -> Void
  ) -> some View {
    PullToRefreshContainer(config: config, onRefresh: onRefresh) {
      self
    }
  }
}

// MARK: - Preview

#Preview {
  struct PreviewContainer: View {
    @State private var refreshCount = 0

    var body: some View {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        VStack(spacing: Spacing.mlg) {
          Text("Pull down to refresh")
            .font(.headline)
            .foregroundColor(.tidexTextPrimary)

          Text("Refreshed \(refreshCount) times")
            .font(.subheadline)
            .foregroundColor(.tidexTextSecondary)
        }
      }
      .pullToRefresh {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        refreshCount += 1
      }
    }
  }

  return PreviewContainer()
}
