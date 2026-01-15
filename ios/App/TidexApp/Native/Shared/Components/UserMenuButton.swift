import SwiftUI

/// A user menu button that displays the user's profile picture and name,
/// with a dropdown menu containing settings and logout options.
/// Inspired by the web UserMenu component.
struct UserMenuButton: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    /// User's display name (email or name from profile)
    let displayName: String
    /// Optional profile picture URL
    let avatarUrl: String?
    /// Whether the sign out action is in progress
    @State private var isSigningOut = false
    /// Cached profile image (downloaded once, then reused)
    @State private var cachedImage: Image?
    /// Whether image download is in progress
    @State private var isLoadingImage = false
    /// Track the URL we've loaded to detect changes
    @State private var loadedUrl: String?
    /// Whether to show the sync debug sheet
    @State private var showSyncDebug = false

    /// Whether debug features are enabled (DEBUG builds only)
    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        Menu {
            // Settings button (disabled for now - no settings page yet)
            Button {
                // TODO: Navigate to settings when page is created
            } label: {
                Label(
                    localization.string("userMenu.settings"),
                    systemImage: "gearshape"
                )
            }
            .disabled(true)

            // Sync Debug button (DEBUG builds only)
            if isDebugBuild {
                Button {
                    showSyncDebug = true
                } label: {
                    Label(
                        "Sync Debug",
                        systemImage: "arrow.triangle.2.circlepath.circle"
                    )
                }
            }

            Divider()

            // Logout button
            Button(role: .destructive) {
                Task {
                    await signOut()
                }
            } label: {
                if isSigningOut {
                    Label(
                        localization.string("userMenu.loggingOut"),
                        systemImage: "arrow.counterclockwise"
                    )
                } else {
                    Label(
                        localization.string("userMenu.logout"),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                }
            }
            .disabled(isSigningOut)
        } label: {
            menuButton
        }
        .sheet(isPresented: $showSyncDebug) {
            NavigationStack {
                SyncDebugView()
            }
        }
    }

    // MARK: - Computed Properties

    /// Extract first name only from display name
    private var firstName: String {
        displayName.components(separatedBy: " ").first ?? displayName
    }

    // MARK: - Menu Button Label

    private var menuButton: some View {
        HStack(spacing: 8) {
            // First name only (no truncation needed for first name)
            Text(firstName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextPrimary)
                .lineLimit(1)

            // Profile picture or initial
            profileImage
        }
    }

    // MARK: - Profile Image

    @ViewBuilder
    private var profileImage: some View {
        Group {
            if let cached = cachedImage {
                // Use cached image
                cached
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: avatarUrl) { oldUrl, newUrl in
            // If URL changes, reload image
            if newUrl != loadedUrl {
                cachedImage = nil
                loadedUrl = nil
                loadImageIfNeeded()
            }
        }
    }

    /// Download and cache the profile image
    private func loadImageIfNeeded() {
        guard let urlString = avatarUrl,
              let url = URL(string: urlString),
              loadedUrl != urlString,
              !isLoadingImage else {
            return
        }

        isLoadingImage = true

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        cachedImage = Image(uiImage: uiImage)
                        loadedUrl = urlString
                        isLoadingImage = false
                    }
                } else {
                    await MainActor.run {
                        isLoadingImage = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingImage = false
                }
            }
        }
    }

    private var initialAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.tidexBlue.opacity(0.2))

            Text(displayName.prefix(1).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.tidexBlue)
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Actions

    private func signOut() async {
        isSigningOut = true
        await coordinator.signOut()
        isSigningOut = false
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.tidexLaunchBackground
            .ignoresSafeArea()

        VStack(spacing: 20) {
            // Shows "John" (first name only)
            UserMenuButton(
                displayName: "John Doe",
                avatarUrl: nil
            )

            // Shows "jane@example.com" (no space = full string)
            UserMenuButton(
                displayName: "jane@example.com",
                avatarUrl: "https://example.com/avatar.jpg"
            )

            // Shows "Hjalmar" (first name only from full name)
            UserMenuButton(
                displayName: "Hjalmar Samuelsson-Kristensen",
                avatarUrl: nil
            )
        }
    }
    .environmentObject(AppCoordinator.shared)
    .environment(\.localization, LocalizationManager.shared)
}
