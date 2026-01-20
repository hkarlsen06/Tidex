import SwiftUI

/// A user menu button that displays the user's profile picture and name,
/// with a dropdown menu for accessing settings.
/// Inspired by the web UserMenu component.
struct UserMenuButton: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    /// User's display name (email or name from profile)
    let displayName: String
    /// Optional profile picture URL
    let avatarUrl: String?
    /// Cached profile image (downloaded once, then reused)
    @State private var cachedImage: UIImage?
    /// Whether image download is in progress
    @State private var isLoadingImage = false
    /// Track the URL we've loaded to detect changes
    @State private var loadedUrl: String?
    /// Whether to show the sync debug sheet
    @State private var showSyncDebug = false
    /// Whether to show the settings sheet
    @State private var showSettings = false

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
            // Settings button
            Button {
                showSettings = true
            } label: {
                Label(
                    localization.string("userMenu.settings"),
                    systemImage: "gearshape"
                )
            }

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
        } label: {
            menuButton
        }
        .sheet(isPresented: $showSyncDebug) {
            NavigationStack {
                SyncDebugView()
            }
            .preferredColorScheme(appearanceManager.colorScheme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .preferredColorScheme(appearanceManager.colorScheme)
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
            // First name only, truncates if too long
            Text(firstName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Profile picture or initial
            profileImage
        }
        // Fixed width ensures consistent toolbar spacing so the logo stays centered
        .frame(width: 110, alignment: .trailing)
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
                let targetSize = CGSize(width: 28 * displayScale, height: 28 * displayScale)
                let uiImage: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
                    guard let baseImage = UIImage(data: data) else { return nil }
                    return baseImage.preparingThumbnail(of: targetSize) ?? baseImage
                }.value
                await MainActor.run {
                    if let uiImage = uiImage {
                        cachedImage = uiImage
                        loadedUrl = urlString
                    }
                    isLoadingImage = false
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
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.tidexBackground
            .ignoresSafeArea()

        VStack(spacing: 20) {
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
    .environment(\.localization, LocalizationManager.shared)
}
