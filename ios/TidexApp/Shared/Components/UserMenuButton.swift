import SwiftUI

/// A user menu button that displays the user's profile picture and name,
/// with a dropdown menu for accessing settings and other quick actions.
/// Inspired by the web UserMenu component.
struct UserMenuButton: View {
  @Environment(\.displayScale) private var displayScale
  // Theme is handled at UIKit window level - sheets inherit from window

  /// User's display name (email or name from profile)
  let displayName: String
  /// Optional profile picture URL
  let avatarUrl: String?
  /// Whether tapping opens settings (true) or is display-only (false)
  var interactive: Bool = true
  /// Cached profile image (downloaded once, then reused)
  @State private var cachedImage: UIImage?
  /// Whether image download is in progress
  @State private var isLoadingImage = false
  /// Track the URL we've loaded to detect changes
  @State private var loadedUrl: String?
  /// Task for loading image (allows cancellation when URL changes)
  @State private var loadTask: Task<Void, Never>?
  /// Whether to show the settings sheet
  @State private var showSettings = false

  var body: some View {
    if interactive {
      Button {
        showSettings = true
      } label: {
        menuButton
      }
      .sheet(isPresented: $showSettings) {
        SettingsView()
      }
    } else {
      menuButton
    }
  }

  // MARK: - Computed Properties

  /// Extract first name only from display name
  private var firstName: String {
    displayName.components(separatedBy: " ").first ?? displayName
  }

  // MARK: - Menu Button Label

  private var menuButton: some View {
    HStack(spacing: Spacing.xs) {
      // First name only, truncates if too long
      Text(firstName)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 80)  // Limit text width to prevent overly long names

      // Profile picture or initial
      profileImage
    }
    .padding(.leading, Spacing.xxxs)
    .padding(.trailing, Spacing.xxs)
    .padding(.vertical, Spacing.xxs)
    // Fixed height prevents toolbar layout shifts on iPad
    .iPadFixedHeight(36)
  }

  // MARK: - Profile Image

  @ViewBuilder
  private var profileImage: some View {
    Group {
      if let cached = cachedImage {
        // Use cached image
        Image(uiImage: cached)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else if isLoadingImage {
        // Show loading indicator while downloading
        ProgressView()
          .frame(width: 28, height: 28)
      } else if avatarUrl != nil {
        // Placeholder while we trigger load
        initialAvatar
          .onAppear {
            loadImageIfNeeded()
          }
      } else {
        // No URL, show initial
        initialAvatar
      }
    }
    .frame(width: 28, height: 28)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    .onChange(of: avatarUrl) { oldUrl, newUrl in
      // If URL changes, cancel any in-progress load and reload
      if newUrl != loadedUrl {
        // Cancel any existing load to prevent race conditions
        loadTask?.cancel()
        loadTask = nil
        cachedImage = nil
        loadedUrl = nil
        isLoadingImage = false
        loadImageIfNeeded()
      }
    }
  }

  /// Download and cache the profile image
  private func loadImageIfNeeded() {
    guard let urlString = avatarUrl,
      let url = URL(string: urlString),
      loadedUrl != urlString,
      !isLoadingImage
    else {
      return
    }

    isLoadingImage = true

    loadTask = Task {
      do {
        let (data, _) = try await URLSession.shared.data(from: url)

        // Check for cancellation before processing
        guard !Task.isCancelled else { return }

        let targetSize = CGSize(width: 28 * displayScale, height: 28 * displayScale)
        let uiImage: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
          guard let baseImage = UIImage(data: data) else { return nil }
          return baseImage.preparingThumbnail(of: targetSize) ?? baseImage
        }.value

        // Check for cancellation before updating state
        guard !Task.isCancelled else { return }

        await MainActor.run {
          // Double-check this is still the URL we want
          guard urlString == avatarUrl else { return }
          if let uiImage = uiImage {
            cachedImage = uiImage
            loadedUrl = urlString
          } else {
            // Image parsing failed - mark as loaded to prevent infinite retries
            loadedUrl = urlString
          }
          isLoadingImage = false
        }
      } catch {
        // Don't update state if cancelled
        guard !Task.isCancelled else { return }
        await MainActor.run {
          isLoadingImage = false
        }
      }
    }
  }

  private var initialAvatar: some View {
    ZStack {
      RoundedRectangle(cornerRadius: CornerRadius.md)
        .fill(Color.tidexBlue.opacity(0.2))

      Text(displayName.prefix(1).uppercased())
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexBlue)
    }
    .frame(width: 28, height: 28)
  }
}

// MARK: - Preview

#Preview {
  ZStack {
    Color.tidexBackground
      .ignoresSafeArea()

    VStack(spacing: Spacing.mlg) {
      // Shows "John"
      UserMenuButton(
        displayName: "John Doe",
        avatarUrl: nil
      )

      // Shows "jane@exam…" (truncated by frame constraint)
      UserMenuButton(
        displayName: "jane@example.com",
        avatarUrl: "https://example.com/avatar.jpg"
      )

      // Shows "Hjalmar"
      UserMenuButton(
        displayName: "Hjalmar Samuelsson-Kristensen",
        avatarUrl: nil
      )

      // Shows "Christoph…" (truncated by frame constraint)
      UserMenuButton(
        displayName: "Christopherson McAllister",
        avatarUrl: nil
      )
    }
  }
  .environmentObject(AppCoordinator.shared)
}
