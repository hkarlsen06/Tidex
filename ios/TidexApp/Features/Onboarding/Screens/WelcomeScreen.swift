import SwiftUI

/// Screen 1: Welcome/Hero
/// Establishes brand, creates emotional connection, sets expectation
struct WelcomeScreen: View {
  let currency: String

  // Entrance animation states - animate once, then stillness
  @State private var showLogo = false
  @State private var showCard = false
  @State private var showHeadline = false
  @State private var showSubheadline = false

  var body: some View {
    VStack(spacing: 0) {
      Spacer()
        .frame(height: 48)

      // Logo anchored in subtle card container
      logoSection
        .opacity(showLogo ? 1 : 0)
        .offset(y: showLogo ? 0 : 8)

      // Ghosted paycheck preview - deliberately obscured
      ghostedPaycheckPreview
        .opacity(showCard ? 1 : 0)
        .offset(y: showCard ? 0 : 12)

      Spacer()

      // Headline and subheadline at bottom
      textContent

      Spacer()
        .frame(height: 120)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      // Staggered entrance choreography - motion with a cause, then stillness
      withAnimation(.easeOut(duration: 0.4)) {
        showLogo = true
      }
      withAnimation(.easeOut(duration: 0.45).delay(0.12)) {
        showCard = true
      }
      withAnimation(.easeOut(duration: 0.4).delay(0.24)) {
        showHeadline = true
      }
      withAnimation(.easeOut(duration: 0.4).delay(0.34)) {
        showSubheadline = true
      }
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private var logoSection: some View {
    ZStack {
      // Soft card glow anchoring the logo - makes it feel grounded
      RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous)
        .fill(
          RadialGradient(
            gradient: Gradient(colors: [
              Color.tidexBlue.opacity(0.08),
              Color.tidexBlue.opacity(0.02),
              Color.clear,
            ]),
            center: .center,
            startRadius: 20,
            endRadius: 100
          )
        )
        .frame(width: 180, height: 180)

      // Tidex logo from assets (transparent)
      Image("TidexLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 120, height: 120)
    }
  }

  /// Sample amount for the ghosted preview driven by selected currency wage defaults.
  private var ghostedAmountText: String {
    let hourlyWage = OnboardingCurrencyResolver.defaultHourlyWage(for: currency)
    let estimatedMonthlyHours = 162.0
    let estimatedNet = hourlyWage * estimatedMonthlyHours * 0.8
    return CurrencyConfig.format(estimatedNet, currency: currency)
  }

  @ViewBuilder
  private var ghostedPaycheckPreview: some View {
    // Deliberately obscured UI - "I can tell this is real, but I'm not allowed to read it yet"
    ZStack {
      VStack(spacing: Spacing.xs) {
        // Fake header bar
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextSecondary)
          .frame(width: 80, height: 8)

        Spacer().frame(height: 4)

        // Large "amount" - the visual hook (locale-aware)
        Text(ghostedAmountText)
          .font(.tidexAmountLarge)
          .foregroundColor(.tidexBlue)

        Spacer().frame(height: 8)

        // Fake breakdown rows - slightly higher contrast
        HStack {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 80, height: 6)
          Spacer()
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 55, height: 6)
        }

        HStack {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 65, height: 6)
          Spacer()
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 50, height: 6)
        }

        HStack {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 90, height: 6)
          Spacer()
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 60, height: 6)
        }
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.mlg)
      .frame(width: 280)
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
          .stroke(Color.tidexBorder, lineWidth: 1)
      )

      // Gradient mask: top opaque → bottom transparent
      // Creates "deliberately obscured" not "vaguely blurred"
      LinearGradient(
        gradient: Gradient(stops: [
          .init(color: Color.tidexBackground, location: 0.0),
          .init(color: Color.tidexBackground.opacity(0.85), location: 0.3),
          .init(color: Color.tidexBackground.opacity(0.4), location: 0.7),
          .init(color: Color.clear, location: 1.0),
        ]),
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(width: 280, height: 180)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    }
    .opacity(0.9)
    .blur(radius: 0.5)
  }

  @ViewBuilder
  private var textContent: some View {
    VStack(spacing: Spacing.sm) {
      // Headline - sized to never truncate on any device
      Text(.onboardingWelcomeTitle)
        .font(.tidexLargeTitle)
        .foregroundStyle(
          LinearGradient(
            colors: [.tidexBlue, .tidexBlue.opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(showHeadline ? 1 : 0)
        .offset(y: showHeadline ? 0 : 8)

      // Subheadline
      Text(.onboardingWelcomeSubtitle)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(showSubheadline ? 1 : 0)
        .offset(y: showSubheadline ? 0 : 6)
    }
    .padding(.horizontal, Spacing.xxl)
    .adaptiveContentWidth()
  }
}

#Preview {
  WelcomeScreen(currency: "kr")
    .background(Color.tidexBackground)
}
