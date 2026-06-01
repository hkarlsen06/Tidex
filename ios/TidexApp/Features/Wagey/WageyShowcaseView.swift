import SwiftUI
import UIKit

/// Showcase view shown to free users on their first visit to Wagey
/// Highlights features and provides a "Try Wagey" button
struct WageyShowcaseView: View {
  private let ctaButtonHeight: CGFloat = 56
  private let ctaFadeStartOffset: CGFloat = Spacing.xl
  private let ctaBottomPadding: CGFloat = Spacing.sm

  private var showcaseCTAHeight: CGFloat {
    ctaButtonHeight + ctaFadeStartOffset + ctaBottomPadding
  }

  @StateObject private var orientationTracker = OrientationTracker.shared
  @EnvironmentObject private var coordinator: AppCoordinator

  /// Callback when user taps "Try Wagey"
  let onTryWagey: () -> Void

  private var isIPadLandscape: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && orientationTracker.isLandscape
  }

  private var heroTopContentSpacing: CGFloat {
    isIPadLandscape ? 108 : 44
  }

  private var userName: String {
    let name = coordinator.userDisplayName
    return name.isEmpty
      ? String(localized: .wageyShowcaseExamplesYou)
      : name.components(separatedBy: " ").first ?? name
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        ScrollView {
          VStack(spacing: 0) {
            VStack(spacing: 0) {
              heroSection(height: heroHeight(for: geometry))

              examplesSection
                .frame(maxWidth: isIPadLandscape ? AdaptiveMaxWidth.tabContent : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

              Spacer(minLength: Spacing.lg)
            }
            .frame(
              minHeight: firstScreenContentMinHeight(for: geometry),
              alignment: .top
            )

            featuresSection
              .frame(maxWidth: isIPadLandscape ? AdaptiveMaxWidth.tabContent : .infinity)
              .frame(maxWidth: .infinity)
              .padding(.horizontal, Spacing.lg)
              .padding(.top, Spacing.lg)
              .padding(.bottom, Spacing.lg + showcaseCTAHeight)
          }
        }

        bottomFadeOverlay(for: geometry)

        tryButton
          .frame(maxWidth: isIPadLandscape ? AdaptiveMaxWidth.tabContent : .infinity)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, ctaBottomPadding)
      }
    }
    .background(Color.tidexBackground)
    .ignoresSafeArea(edges: .top)
  }

  private func bottomFadeOverlay(for geometry: GeometryProxy) -> some View {
    let bottomInset = geometry.safeAreaInsets.bottom

    return LinearGradient(
      stops: [
        .init(color: Color.tidexBackground.opacity(0), location: 0),
        .init(color: Color.tidexBackground.opacity(0.82), location: 0.42),
        .init(color: Color.tidexBackground.opacity(0.98), location: 0.68),
        .init(color: Color.tidexBackground, location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(height: showcaseCTAHeight + bottomInset + Spacing.xl)
    .frame(maxWidth: .infinity)
    .offset(y: bottomInset)
    .ignoresSafeArea(edges: .bottom)
    .allowsHitTesting(false)
  }

  private func heroHeight(for geometry: GeometryProxy) -> CGFloat {
    let windowMetrics = activeWindowMetrics
    let screenBounds = windowMetrics.screenBounds
    let screenInsets = windowMetrics.safeAreaInsets
    let screenHeight = max(screenBounds.height, geometry.size.height)
    let topInset = screenInsets.top
    let bottomChromeHeight = showcaseCTAHeight + screenInsets.bottom + tabBarReservedHeight
    let availableHeight = max(screenHeight - topInset - bottomChromeHeight, 0)

    return topInset + availableHeight * 0.40
  }

  private var activeWindowMetrics: (screenBounds: CGRect, safeAreaInsets: UIEdgeInsets) {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)

    return (
      screenBounds: keyWindow?.windowScene?.screen.bounds ?? .zero,
      safeAreaInsets: keyWindow?.safeAreaInsets ?? .zero
    )
  }

  private var tabBarReservedHeight: CGFloat {
    UIDevice.current.userInterfaceIdiom == .pad ? 0 : 49
  }

  private func firstScreenContentMinHeight(for geometry: GeometryProxy) -> CGFloat {
    max(geometry.size.height - geometry.safeAreaInsets.bottom + ctaButtonHeight, 0)
  }

  // MARK: - Hero Section

  private func heroSection(height: CGFloat) -> some View {
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
          .frame(height: heroTopContentSpacing)

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
    .frame(height: height)
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
      Haptics.play(.success)
      onTryWagey()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "play.fill")
          .font(.tidexLabelStrong)

        Text(.wageyShowcaseHeroTryButton)
          .font(.tidexHeadline)
      }
      .frame(maxWidth: .infinity)
      .frame(height: ctaButtonHeight)
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
