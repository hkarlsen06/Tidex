import SwiftUI
import UIKit

/// Showcase view shown to free users on their first visit to Wagey
/// Highlights features and provides a "Try Wagey" button
struct WageyShowcaseView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  private let ctaButtonHeight: CGFloat = 56
  private let ctaFadeStartOffset: CGFloat = Spacing.xl
  private let ctaBottomPadding: CGFloat = Spacing.sm

  private var showcaseCTAHeight: CGFloat {
    ctaButtonHeight + ctaFadeStartOffset + ctaBottomPadding
  }

  @StateObject private var orientationTracker = OrientationTracker.shared  // swiftlint:disable:this explicit_type_interface line_length
  @EnvironmentObject private var coordinator: AppCoordinator

  /// Callback when user taps "Try Wagey"
  let onTryWagey: () -> Void  // swiftlint:disable:this explicit_acl

  private var isIPadLandscape: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && orientationTracker.isLandscape
  }

  private var heroTopContentSpacing: CGFloat {
    isIPadLandscape ? 108 : 44  // swiftlint:disable:this no_magic_numbers
  }

  private var userName: String {
    let name = coordinator.userDisplayName  // swiftlint:disable:this explicit_type_interface
    return name.isEmpty
      ? String(localized: .wageyShowcaseExamplesYou)
      : name.components(separatedBy: " ").first ?? name
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    GeometryReader { geometry in  // swiftlint:disable:this closure_body_length
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

  private func bottomFadeOverlay(for geometry: GeometryProxy) -> some View {  // swiftlint:disable:this line_length type_contents_order
    let bottomInset = geometry.safeAreaInsets.bottom  // swiftlint:disable:this explicit_type_interface

    return LinearGradient(
      stops: [
        .init(color: Color.tidexBackground.opacity(0), location: 0),
        .init(color: Color.tidexBackground.opacity(0.82), location: 0.42),  // swiftlint:disable:this no_magic_numbers
        .init(color: Color.tidexBackground.opacity(0.98), location: 0.68),  // swiftlint:disable:this no_magic_numbers
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

  private func heroHeight(for geometry: GeometryProxy) -> CGFloat {  // swiftlint:disable:this type_contents_order
    let windowMetrics = activeWindowMetrics  // swiftlint:disable:this explicit_type_interface
    let screenBounds = windowMetrics.screenBounds  // swiftlint:disable:this explicit_type_interface
    let screenInsets = windowMetrics.safeAreaInsets  // swiftlint:disable:this explicit_type_interface
    let screenHeight = max(screenBounds.height, geometry.size.height)  // swiftlint:disable:this explicit_type_interface
    let topInset = screenInsets.top  // swiftlint:disable:this explicit_type_interface
    let bottomChromeHeight = showcaseCTAHeight + screenInsets.bottom + tabBarReservedHeight  // swiftlint:disable:this explicit_type_interface line_length
    let availableHeight = max(screenHeight - topInset - bottomChromeHeight, 0)  // swiftlint:disable:this explicit_type_interface line_length

    return topInset + availableHeight * 0.40  // swiftlint:disable:this no_magic_numbers
  }

  private var activeWindowMetrics: (screenBounds: CGRect, safeAreaInsets: UIEdgeInsets) {
    let keyWindow = UIApplication.shared.connectedScenes  // swiftlint:disable:this explicit_type_interface
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)

    return (
      screenBounds: keyWindow?.windowScene?.screen.bounds ?? .zero,
      safeAreaInsets: keyWindow?.safeAreaInsets ?? .zero
    )
  }

  private var tabBarReservedHeight: CGFloat {
    UIDevice.current.userInterfaceIdiom == .pad ? 0 : 49  // swiftlint:disable:this no_magic_numbers
  }

  private func firstScreenContentMinHeight(for geometry: GeometryProxy) -> CGFloat {  // swiftlint:disable:this line_length type_contents_order
    max(geometry.size.height - geometry.safeAreaInsets.bottom + ctaButtonHeight, 0)
  }

  // MARK: - Hero Section

  private func heroSection(height: CGFloat) -> some View {  // swiftlint:disable:this function_body_length line_length type_contents_order
    ZStack {  // swiftlint:disable:this closure_body_length
      // Gradient background
      LinearGradient(
        colors: [
          Color(red: 0.35, green: 0.45, blue: 0.95),  // swiftlint:disable:this no_magic_numbers
          Color(red: 0.55, green: 0.35, blue: 0.9),  // swiftlint:disable:this no_magic_numbers
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      // Decorative blurred circles
      Circle()
        .fill(Color.white.opacity(0.15))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 200, height: 200)  // swiftlint:disable:this no_magic_numbers
        .blur(radius: 50)  // swiftlint:disable:this no_magic_numbers
        .offset(x: -100, y: -30)  // swiftlint:disable:this no_magic_numbers

      Circle()
        .fill(Color.white.opacity(0.1))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 150, height: 150)  // swiftlint:disable:this no_magic_numbers
        .blur(radius: 40)  // swiftlint:disable:this no_magic_numbers
        .offset(x: 120, y: 50)  // swiftlint:disable:this no_magic_numbers

      // Content
      VStack(spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
        Spacer()
          .frame(height: heroTopContentSpacing)

        HStack(spacing: Spacing.md) {
          // Sparkles icon with glow
          ZStack {
            Circle()
              .fill(Color.white.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
              .frame(width: 88, height: 88)  // swiftlint:disable:this no_magic_numbers
              .blur(radius: 22)  // swiftlint:disable:this no_magic_numbers

            Circle()
              .fill(
                LinearGradient(
                  colors: [.white.opacity(0.35), .white.opacity(0.15)],  // swiftlint:disable:this no_magic_numbers
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
              .frame(width: 70, height: 70)  // swiftlint:disable:this no_magic_numbers

            Image(systemName: "sparkles")  // swiftlint:disable:this accessibility_label_for_image
              .font(.system(size: 32, weight: .medium))  // swiftlint:disable:this no_magic_numbers
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
          .foregroundStyle(.white.opacity(0.9))  // swiftlint:disable:this no_magic_numbers
          .multilineTextAlignment(.center)
          .padding(.horizontal, Spacing.lg)

        Spacer()
          .frame(height: 20)  // swiftlint:disable:this no_magic_numbers
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

  private func featureCard(  // swiftlint:disable:this function_body_length type_contents_order
    icon: String,
    titleKey: LocalizedStringResource,
    descriptionKey: LocalizedStringResource
  ) -> some View {
    HStack(alignment: .top, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
      ZStack {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.15),  // swiftlint:disable:this no_magic_numbers
                Color(red: 0.55, green: 0.35, blue: 0.9).opacity(0.1),  // swiftlint:disable:this no_magic_numbers
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 44, height: 44)  // swiftlint:disable:this no_magic_numbers

        Image(systemName: icon)  // swiftlint:disable:this accessibility_label_for_image
          .font(.tidexHeadline)
          .foregroundStyle(
            LinearGradient(
              colors: [
                Color(red: 0.35, green: 0.45, blue: 0.95),  // swiftlint:disable:this no_magic_numbers
                Color(red: 0.55, green: 0.35, blue: 0.9),  // swiftlint:disable:this no_magic_numbers
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
    .background(Color.tidexSurfaceSecondary.opacity(0.5))  // swiftlint:disable:this no_magic_numbers
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)  // swiftlint:disable:this no_magic_numbers
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
            )),  // swiftlint:disable:this multiline_arguments_brackets
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
      .background(Color.tidexSurfaceSecondary.opacity(0.35))  // swiftlint:disable:this no_magic_numbers
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxxl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxxl, style: .continuous)
          .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)  // swiftlint:disable:this no_magic_numbers
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
        Image(systemName: "play.fill")  // swiftlint:disable:this accessibility_label_for_image
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
            Color(red: 0.35, green: 0.45, blue: 0.95),  // swiftlint:disable:this no_magic_numbers
            Color(red: 0.55, green: 0.35, blue: 0.9),  // swiftlint:disable:this no_magic_numbers
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .shadow(color: Color(red: 0.45, green: 0.4, blue: 0.9).opacity(0.3), radius: 12, y: 6)  // swiftlint:disable:this line_length no_magic_numbers
    }
  }
}

// MARK: - Preview

#Preview {
  WageyShowcaseView(onTryWagey: { print("Try Wagey tapped") })  // swiftlint:disable:this no_direct_print
    .environmentObject(AppCoordinator.shared)
}
