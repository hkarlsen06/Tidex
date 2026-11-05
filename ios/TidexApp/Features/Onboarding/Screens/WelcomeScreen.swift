import SwiftUI
import UIKit

/// Screen 1: Welcome/Hero
/// Establishes brand, creates emotional connection, sets expectation
struct WelcomeScreen: View {
  let currency: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  // Entrance animation states - animate once, then stillness
  @State private var showCard = false
  @State private var showHeadline = false
  @State private var showSubheadline = false

  private var heroTitleFont: Font {
    let size = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 44)
    return .system(size: size, weight: .semibold, design: .default)
  }

  private var heroSubtitleFont: Font {
    let size = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17)
    return .system(size: size, weight: .regular, design: .default)
  }

  /// From this size on the title wraps naturally instead of shrinking on two fixed lines.
  private var usesFlowingTitle: Bool {
    dynamicTypeSize >= .xxLarge
  }

  private var titleLines: [String] {
    let title = String(localized: .onboardingWelcomeTitle)
    let words = title.split(separator: " ").map(String.init)
    guard words.count > 3 else { return [title] }

    let targetLength = Double(title.count) / 2
    var bestSplitIndex = 1
    var bestDistance = Double.greatestFiniteMagnitude

    for splitIndex in 1..<words.count {
      let firstLineLength = words[..<splitIndex].joined(separator: " ").count
      let distance = abs(Double(firstLineLength) - targetLength)
      if distance < bestDistance {
        bestDistance = distance
        bestSplitIndex = splitIndex
      }
    }

    return [
      words[..<bestSplitIndex].joined(separator: " "),
      words[bestSplitIndex...].joined(separator: " "),
    ]
  }

  var body: some View {
    GeometryReader { geometry in
      let usesColumns = geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize

      ScrollView {
        heroContent(usesColumns: usesColumns, availableHeight: geometry.size.height)
          .frame(maxWidth: 820)
          .padding(.horizontal, Spacing.xl)
          .frame(maxWidth: .infinity)
          .padding(.vertical, geometry.size.height < 400 ? Spacing.xs : Spacing.lg)
          .frame(minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
      .clipped()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      // Staggered entrance choreography - motion with a cause, then stillness
      withAnimation(.easeOut(duration: 0.4)) {
        showHeadline = true
      }
      withAnimation(.easeOut(duration: 0.4).delay(0.08)) {
        showSubheadline = true
      }
      withAnimation(.easeOut(duration: 0.45).delay(0.16)) {
        showCard = true
      }
    }
  }

  // MARK: - Subviews

  private func heroContent(usesColumns: Bool, availableHeight: CGFloat) -> some View {
    let layout =
      usesColumns
      ? AnyLayout(HStackLayout(spacing: Spacing.huge))
      : AnyLayout(VStackLayout(spacing: availableHeight < 400 ? Spacing.sm : Spacing.huge))
    return layout {
      textContent
      ghostedPaycheckPreview
        .opacity(showCard ? 1 : 0)
        .offset(y: showCard || reduceMotion ? 0 : 14)
    }
    .frame(maxWidth: .infinity)
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
          .foregroundColor(.tidexBlueText)

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
          .stroke(Color.tidexSeparator, lineWidth: 1)
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
    .accessibilityHidden(true)
  }

  private func heroTitle(
    horizontalAlignment: HorizontalAlignment,
    frameAlignment: Alignment,
    textAlignment: TextAlignment
  ) -> some View {
    Group {
      if usesFlowingTitle {
        Text(.onboardingWelcomeTitle)
          .font(heroTitleFont)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(textAlignment)
          .frame(maxWidth: .infinity, alignment: frameAlignment)
      } else {
        VStack(alignment: horizontalAlignment, spacing: -10) {
          ForEach(Array(titleLines.enumerated()), id: \.offset) { _, line in
            Text(line)
              .font(heroTitleFont)
              .foregroundColor(.tidexTextPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.78)
              .frame(maxWidth: .infinity, alignment: frameAlignment)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.onboardingWelcomeTitle))
      }
    }
    .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder
  private var textContent: some View {
    VStack(spacing: Spacing.sm) {
      heroTitle(
        horizontalAlignment: .leading,
        frameAlignment: .leading,
        textAlignment: .leading
      )
      .opacity(showHeadline ? 1 : 0)
      .offset(y: showHeadline || reduceMotion ? 0 : 8)

      Text(.onboardingWelcomeSubtitle)
        .font(heroSubtitleFont)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.leading)
        .lineSpacing(2)
        .lineLimit(usesFlowingTitle ? nil : 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(showSubheadline ? 1 : 0)
        .offset(y: showSubheadline || reduceMotion ? 0 : 6)

      Text(.onboardingWelcomeFree)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexBlueText)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(showSubheadline ? 1 : 0)
        .offset(y: showSubheadline || reduceMotion ? 0 : 6)
    }
    .frame(maxWidth: 350, alignment: .leading)
  }
}

#Preview {
  WelcomeScreen(currency: "kr")
    .background(Color.tidexBackground)
}
