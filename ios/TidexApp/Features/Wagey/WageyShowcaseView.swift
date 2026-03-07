import SwiftUI

/// Showcase view shown to free users on their first visit to Wagey
/// Highlights features and provides a "Try Wagey" button
struct WageyShowcaseView: View {
  private let showcaseCTAHeight: CGFloat = 56 + Spacing.md + Spacing.sm + 1

  @EnvironmentObject private var coordinator: AppCoordinator

  /// Callback when user taps "Try Wagey"
  let onTryWagey: () -> Void

  private var userName: String {
    let name = coordinator.userDisplayName
    return name.isEmpty
      ? String(localized: .wageyShowcaseExamplesYou)
      : name.components(separatedBy: " ").first ?? name
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            heroSection

            VStack(spacing: Spacing.lg) {
              featuresSection
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)

            Spacer(minLength: Spacing.lg)
          }
          .frame(
            minHeight: max(
              geometry.size.height - geometry.safeAreaInsets.bottom - showcaseCTAHeight, 0),
            alignment: .top
          )

          examplesSection
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
      }
    }
    .background(Color.tidexBackground)
    .ignoresSafeArea(edges: .top)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        Divider()
          .overlay(Color.tidexBorder.opacity(0.4))

        tryButton
          .padding(.horizontal, Spacing.lg)
          .padding(.top, Spacing.md)
          .padding(.bottom, Spacing.sm)
          .background(Color.tidexBackground.opacity(0.96))
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
          Color(red: 0.55, green: 0.35, blue: 0.9),
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
      VStack(spacing: Spacing.md) {
        Spacer()
          .frame(height: 44)

        HStack(spacing: Spacing.md) {
          // Sparkles icon with glow
          ZStack {
            Circle()
              .fill(Color.white.opacity(0.3))
              .frame(width: 88, height: 88)
              .blur(radius: 22)

            Circle()
              .fill(
                LinearGradient(
                  colors: [.white.opacity(0.35), .white.opacity(0.15)],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
              .frame(width: 70, height: 70)

            Image(systemName: "sparkles")
              .font(.system(size: 32, weight: .medium))
              .foregroundStyle(.white)
          }

          Text(.wageyShowcaseHeroTitle)
            .font(.tidexAmountLarge)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, Spacing.lg)

        // Subtitle
        Text(.wageyShowcaseHeroSubtitle)
          .font(.tidexBodyMedium)
          .foregroundStyle(.white.opacity(0.9))
          .multilineTextAlignment(.center)
          .padding(.horizontal, Spacing.lg)

        Spacer()
          .frame(height: 20)
      }
    }
    .frame(minHeight: 236)
  }

  // MARK: - Features Section

  private var featuresSection: some View {
    VStack(spacing: Spacing.md) {
      VStack(spacing: Spacing.sm) {
        featureCard(
          icon: "message.fill",
          titleKey: .wageyShowcaseFeaturesNaturalLanguageTitle,
          descriptionKey: .wageyShowcaseFeaturesNaturalLanguageDescription
        )

        featureCard(
          icon: "bolt.fill",
          titleKey: .wageyShowcaseFeaturesQuickActionsTitle,
          descriptionKey: .wageyShowcaseFeaturesQuickActionsDescription
        )

        featureCard(
          icon: "creditcard.fill",
          titleKey: .wageyShowcaseFeaturesWageCalculationsTitle,
          descriptionKey: .wageyShowcaseFeaturesWageCalculationsDescription
        )

        featureCard(
          icon: "calendar",
          titleKey: .wageyShowcaseFeaturesSchedulingTitle,
          descriptionKey: .wageyShowcaseFeaturesSchedulingDescription
        )
      }
    }
  }

  private func featureCard(
    icon: String,
    titleKey: LocalizedStringResource,
    descriptionKey: LocalizedStringResource
  ) -> some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      ZStack {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.15),
                Color(red: 0.55, green: 0.35, blue: 0.9).opacity(0.1),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 44, height: 44)

        Image(systemName: icon)
          .font(.tidexHeadline)
          .foregroundStyle(
            LinearGradient(
              colors: [
                Color(red: 0.35, green: 0.45, blue: 0.95),
                Color(red: 0.55, green: 0.35, blue: 0.9),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      }

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(String(localized: titleKey))
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)
          .fixedSize(horizontal: false, vertical: true)

        Text(String(localized: descriptionKey))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
    )
  }

  // MARK: - Example Section

  private var exampleConversation: [ChatMessage] {
    [
      ChatMessage(
        id: "showcase-user",
        role: .user,
        content: String(localized: .wageyShowcaseExamplesExample1User),
        toolCalls: nil,
        timestamp: Date()
      ),
      ChatMessage(
        id: "showcase-assistant",
        role: .assistant,
        contentBlocks: [
          .toolCall(
            ToolCall(
              id: "showcase-tool",
              name: "manage_shift",
              arguments: nil,
              result: "{\"success\": true}",
              success: true
            )),
          .text(String(localized: .wageyShowcaseExamplesExample1Assistant)),
        ],
        timestamp: Date()
      ),
    ]
  }

  private var examplesSection: some View {
    VStack(spacing: Spacing.md) {
      Text(.wageyShowcaseExamplesTitle)
        .font(.tidexTitle2)
        .foregroundColor(.tidexTextPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: Spacing.xs) {
        ForEach(exampleConversation) { message in
          VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xxs) {
            Text(message.role == .user ? userName : "Wagey")
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
              .padding(.horizontal, Spacing.xxs)

            ChatMessageBubble(message: message)
          }
          .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfaceSecondary.opacity(0.35))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxxl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxxl, style: .continuous)
          .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
      )
    }
  }

  // MARK: - Try Button

  private var tryButton: some View {
    Button {
      onTryWagey()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "play.fill")
          .font(.tidexLabelStrong)

        Text(.wageyShowcaseHeroTryButton)
          .font(.tidexHeadline)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .foregroundStyle(.white)
      .background(
        LinearGradient(
          colors: [
            Color(red: 0.35, green: 0.45, blue: 0.95),
            Color(red: 0.55, green: 0.35, blue: 0.9),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .shadow(color: Color(red: 0.45, green: 0.4, blue: 0.9).opacity(0.3), radius: 12, y: 6)
    }
  }
}

// MARK: - Preview

#Preview {
  WageyShowcaseView(onTryWagey: { print("Try Wagey tapped") })
    .environmentObject(AppCoordinator.shared)
}
