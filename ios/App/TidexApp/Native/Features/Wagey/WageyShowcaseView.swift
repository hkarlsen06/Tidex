import SwiftUI

/// Showcase view shown to free users on their first visit to Wagey
/// Highlights features and provides a "Try Wagey" button
struct WageyShowcaseView: View {
    @Environment(\.localization) private var localization
    @EnvironmentObject private var coordinator: AppCoordinator

    /// Callback when user taps "Try Wagey"
    let onTryWagey: () -> Void

    /// Callback when user taps close button (closes entire Wagey flow)
    var onClose: (() -> Void)?

    /// User's display name for example conversations
    private var userName: String {
        let name = coordinator.userDisplayName
        return name.isEmpty ? localization.string("wagey.showcase.examples.you") : name.components(separatedBy: " ").first ?? name
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero section
                    heroSection

                    // Content
                    VStack(spacing: 32) {
                        // Features grid
                        featuresSection

                        // Example conversations
                        examplesSection

                        // Try button
                        tryButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 48)
                }
            }
            .background(Color.tidexBackground)
            .ignoresSafeArea(edges: .top)

            // Close button overlay
            if let onClose = onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .padding(.top, 16)
                .padding(.trailing, 20)
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.45, blue: 0.95),
                    Color(red: 0.55, green: 0.35, blue: 0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative blurred circles
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(x: -100, y: -30)

            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 150, height: 150)
                .blur(radius: 40)
                .offset(x: 120, y: 50)

            // Content
            VStack(spacing: 20) {
                // Extra space for status bar
                Spacer()
                    .frame(height: 60)

                // Sparkles icon with glow
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .blur(radius: 25)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }

                // Title
                Text(localization.string("wagey.showcase.hero.title"))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Subtitle
                Text(localization.string("wagey.showcase.hero.subtitle"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                // Description
                Text(localization.string("wagey.showcase.hero.description"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 32)
            }
        }
        .frame(minHeight: 360)
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(spacing: 16) {
            Text(localization.string("wagey.showcase.features.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.tidexTextPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                featureCard(
                    icon: "message.fill",
                    titleKey: "wagey.showcase.features.naturalLanguage.title",
                    descriptionKey: "wagey.showcase.features.naturalLanguage.description"
                )

                featureCard(
                    icon: "bolt.fill",
                    titleKey: "wagey.showcase.features.quickActions.title",
                    descriptionKey: "wagey.showcase.features.quickActions.description"
                )

                featureCard(
                    icon: "creditcard.fill",
                    titleKey: "wagey.showcase.features.wageCalculations.title",
                    descriptionKey: "wagey.showcase.features.wageCalculations.description"
                )

                featureCard(
                    icon: "calendar",
                    titleKey: "wagey.showcase.features.scheduling.title",
                    descriptionKey: "wagey.showcase.features.scheduling.description"
                )
            }
        }
    }

    private func featureCard(icon: String, titleKey: String, descriptionKey: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.15),
                                Color(red: 0.55, green: 0.35, blue: 0.9).opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.45, blue: 0.95),
                                Color(red: 0.55, green: 0.35, blue: 0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string(titleKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string(descriptionKey))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.tidexSurfaceSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Examples Section

    /// Example messages demonstrating Wagey capabilities
    private var exampleMessages: [[ChatMessage]] {
        [
            // Example 1: Adding a shift
            [
                ChatMessage(
                    id: "ex1-user",
                    role: .user,
                    content: localization.string("wagey.showcase.examples.example1User"),
                    toolCalls: nil,
                    timestamp: Date()
                ),
                ChatMessage(
                    id: "ex1-assistant",
                    role: .assistant,
                    contentBlocks: [
                        .toolCall(ToolCall(
                            id: "tool1",
                            name: "manage_shift",
                            arguments: nil,
                            result: "{\"success\": true}",
                            success: true
                        )),
                        .text(localization.string("wagey.showcase.examples.example1Assistant"))
                    ],
                    timestamp: Date()
                )
            ],
            // Example 2: Statistics query
            [
                ChatMessage(
                    id: "ex2-user",
                    role: .user,
                    content: localization.string("wagey.showcase.examples.example2User"),
                    toolCalls: nil,
                    timestamp: Date()
                ),
                ChatMessage(
                    id: "ex2-assistant",
                    role: .assistant,
                    contentBlocks: [
                        .toolCall(ToolCall(
                            id: "tool2",
                            name: "get_statistics",
                            arguments: nil,
                            result: "{\"success\": true}",
                            success: true
                        )),
                        .text(localization.string("wagey.showcase.examples.example2Assistant"))
                    ],
                    timestamp: Date()
                )
            ]
        ]
    }

    private var examplesSection: some View {
        VStack(spacing: 16) {
            Text(localization.string("wagey.showcase.examples.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.tidexTextPrimary)

            VStack(spacing: 16) {
                ForEach(Array(exampleMessages.enumerated()), id: \.offset) { index, conversation in
                    VStack(spacing: 8) {
                        ForEach(conversation) { message in
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                                // Name label
                                Text(message.role == .user ? userName : "Wagey")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.tidexTextMuted)
                                    .padding(.horizontal, 4)

                                // Actual message bubble
                                ChatMessageBubble(message: message)
                            }
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                        }
                    }

                    // Divider between conversations (except after last)
                    if index < exampleMessages.count - 1 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(16)
            .background(Color.tidexBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
            )
        }
    }

    // MARK: - Try Button

    private var tryButton: some View {
        Button {
            Haptics.playSubscriptionSuccess()
            onTryWagey()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))

                Text(localization.string("wagey.showcase.hero.tryButton"))
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.45, blue: 0.95),
                        Color(red: 0.55, green: 0.35, blue: 0.9)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(red: 0.45, green: 0.4, blue: 0.9).opacity(0.3), radius: 12, y: 6)
        }
    }
}

// MARK: - Preview

#Preview {
    WageyShowcaseView(
        onTryWagey: { print("Try Wagey tapped") },
        onClose: { print("Close tapped") }
    )
    .environmentObject(AppCoordinator.shared)
    .environment(\.localization, LocalizationManager.shared)
}
