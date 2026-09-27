import Foundation
import StoreKit
import SwiftUI

/// Shared Pro trial paywall shell. The section below the "or" divider is supplied by the
/// caller so month-limit and Wagey can share the same offer surface.
struct TrialPaywallScaffold<AlternativeContent: View>: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: PaywallViewModel

  let isAlternativeBusy: Bool
  let showsAlternativeSection: Bool
  let showsRestorePurchases: Bool
  let onStartSubscription: (Product) -> Void
  let onRestorePurchases: (() -> Void)?
  @ViewBuilder let alternativeContent: () -> AlternativeContent

  @State private var showFeatureInfo = false

  private let activeTimelineIconSize: CGFloat = 44
  private let inactiveTimelineIconSize: CGFloat = 38
  private let timelineRowHeight: CGFloat = 82

  init(
    viewModel: PaywallViewModel,
    isAlternativeBusy: Bool = false,
    showsAlternativeSection: Bool = true,
    showsRestorePurchases: Bool = false,
    onStartSubscription: @escaping (Product) -> Void,
    onRestorePurchases: (() -> Void)? = nil,
    @ViewBuilder alternativeContent: @escaping () -> AlternativeContent
  ) {
    self.viewModel = viewModel
    self.isAlternativeBusy = isAlternativeBusy
    self.showsAlternativeSection = showsAlternativeSection
    self.showsRestorePurchases = showsRestorePurchases
    self.onStartSubscription = onStartSubscription
    self.onRestorePurchases = onRestorePurchases
    self.alternativeContent = alternativeContent
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.tidexSurfacePrimary
        .ignoresSafeArea()

      ScrollView(showsIndicators: false) {
        VStack(spacing: 0) {
          artworkHeader

          mainOfferContent
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .frame(maxWidth: 462)

          timeline
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xl)
            .frame(maxWidth: 462)

          lowerOptions
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xxl)
            .frame(maxWidth: 462)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.xl)
      }
      .ignoresSafeArea(edges: .top)
    }
    .safeAreaInset(edge: .bottom) {
      bottomCTA
    }
    .presentationBackground(Color.tidexSurfacePrimary)
  }

  private var mainOfferContent: some View {
    VStack(alignment: .leading, spacing: Spacing.mlg) {
      headlineBlock

      if let purchaseError = viewModel.error {
        paywallErrorView(purchaseError)
      }
    }
  }

  private var lowerOptions: some View {
    VStack(spacing: 26) {
      billingSelector

      if showsAlternativeSection {
        dividerWithOr
        alternativeContent()
      }

      if showsRestorePurchases {
        restorePurchasesButton
      }

      legalLinks
        .padding(.top, Spacing.mlg)
    }
  }

  private var artworkHeader: some View {
    ZStack(alignment: .topTrailing) {
      Color.tidexSurfacePrimary

      heroOutcomePreview
        .frame(maxWidth: 462, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, 84)
        .frame(maxWidth: .infinity, alignment: .leading)

      closeButton
    }
    .frame(maxWidth: .infinity)
    .frame(height: 300)
  }

  private var heroOutcomePreview: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(heroSeasonTitle)
          .font(.tidexCaptionStrong)
          .foregroundColor(Color.tidexTextSecondary)
          .textCase(nil)

        Text(verbatim: "50 000 kr")
          .font(.tidexStatSecondary)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.76)

        Text(.monthLimitHeroPreviewSubtitle)
          .font(.tidexFootnoteMedium)
          .foregroundColor(Color.tidexTextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }

      heroIncomeChart
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var heroIncomeChart: some View {
    let values: [CGFloat] = [0.32, 0.4, 0.36, 0.52, 0.62, 0.86, 0.96, 0.78, 0.48, 0.56, 0.44, 0.66]

    return HStack(alignment: .bottom, spacing: 6) {
      ForEach(Array(values.enumerated()), id: \.offset) { index, value in
        VStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(heroChartFill(for: index))
            .frame(height: max(18, value * 62))

          // Unlabeled bars keep a hidden label so every column has the same height at any text size
          Text(heroMonthLabel(for: index))
            .font(.tidexMicro.weight(.bold))
            .foregroundColor(Color.tidexTextMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .opacity(shouldShowHeroMonthLabel(index) ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .frame(minHeight: 88)
    .padding(.top, Spacing.xxs)
    // Decorative illustration of a pay chart
    .accessibilityHidden(true)
  }

  private func heroChartFill(for index: Int) -> Color {
    isHighlightedHeroMonth(index) ? .tidexBlue : .tidexSurfaceSecondary
  }

  private var headlineBlock: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Text(viewModel.offersFreeTrial ? .paywallTrialTitle : .paywallSubscribeTitle)
          .font(.tidexScreenTitle)
          .foregroundColor(Color.tidexTextPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)

        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            showFeatureInfo.toggle()
          }
        } label: {
          Image(systemName: "info.circle.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.tidexTextMuted)
            .frame(width: 44, height: 44)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.paywallPlanProBadge))
      }

      Text(.monthLimitPaywallSubtitle)
        .font(.tidexSubheadline)
        .foregroundColor(Color.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      priceLineView
        .padding(.top, Spacing.xxs)

      if showFeatureInfo {
        proFeatureList
          .padding(.top, Spacing.sm)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  private var proFeatureList: some View {
    VStack(spacing: Spacing.xs) {
      proFeatureRow(icon: "calendar.badge.plus", title: String(localized: .paywallProFeature1))
      proFeatureRow(icon: "sparkles", title: String(localized: .paywallProFeature2))
      proFeatureRow(icon: "person.2.fill", title: String(localized: .paywallProFeature3))
      proFeatureRow(icon: "bolt.heart.fill", title: String(localized: .paywallProFeature4))
    }
  }

  private func proFeatureRow(icon: String, title: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.tidexPurple)
        .frame(width: 26, height: 26)
        .background(Color.tidexPurple.opacity(0.1))
        .clipShape(Circle())

      Text(title)
        .font(.tidexBodyMedium)
        .foregroundColor(Color.tidexTextPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
  }

  private var billingSelector: some View {
    HStack(spacing: Spacing.xxs) {
      billingOption(.monthly)
      billingOption(.yearly)
    }
    .padding(Spacing.xxs)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
  }

  private func billingOption(_ period: BillingPeriod) -> some View {
    let isSelected = viewModel.billingPeriod == period

    return Button {
      withAnimation(.easeOut(duration: 0.18)) {
        viewModel.billingPeriod = period
      }
    } label: {
      VStack(spacing: Spacing.micro) {
        Text(period.displayName)
          .font(isSelected ? .tidexLabelStrong : .tidexLabel)
          .foregroundColor(isSelected ? Color.tidexTextPrimary : Color.tidexTextMuted)

        if period == .yearly,
          let savings = viewModel.yearlySavingsPercent(for: .pro)
        {
          Text(
            String(localized: .paywallSavePercent(FormatterCache.percentagePoints(Double(savings))))
          )
          .font(.tidexMicro.bold())
          .foregroundColor(isSelected ? .tidexBlue : Color.tidexTextMuted)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: 50)
      .background(isSelected ? Color.tidexSurfacePrimary : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isAlternativeBusy || viewModel.isPurchasing)
  }

  private var timeline: some View {
    VStack(spacing: 0) {
      ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
        timelineRow(item: item, isLast: index == timelineItems.count - 1)
      }
    }
  }

  private func timelineRow(item: TrialPaywallTimelineItem, isLast: Bool) -> some View {
    let iconSize = item.isActive ? activeTimelineIconSize : inactiveTimelineIconSize
    let nextIconSize = inactiveTimelineIconSize
    let rowHeight = timelineRowHeight
    let connectorHeight = rowHeight + (nextIconSize / 2) - (iconSize / 2)

    return HStack(alignment: .top, spacing: Spacing.sm) {
      ZStack(alignment: .top) {
        if !isLast {
          Capsule()
            .fill(item.isActive ? Color.tidexSeparator : Color.tidexBorderSubtle)
            .frame(width: 2, height: connectorHeight)
            .offset(y: iconSize / 2)
        }

        ZStack {
          Circle()
            .fill(item.isActive ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
            .frame(width: iconSize, height: iconSize)

          Image(systemName: item.icon)
            .font(.system(size: item.isActive ? 18 : 16, weight: .semibold))
            .foregroundColor(item.isActive ? .tidexTextOnBrand : Color.tidexTextMuted)
        }
      }
      .frame(width: 48, height: isLast ? nil : rowHeight, alignment: .top)

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(item.title)
          .font(.tidexLabelStrong)
          .foregroundColor(Color.tidexTextPrimary)

        Text(item.body)
          .font(.tidexFootnote)
          .foregroundColor(Color.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(minHeight: isLast ? 0 : rowHeight, alignment: .top)

      Spacer(minLength: 0)
    }
    .frame(minHeight: isLast ? 0 : rowHeight, alignment: .top)
  }

  private var primaryCTA: some View {
    Button(action: startPurchase) {
      HStack(spacing: Spacing.xs) {
        if viewModel.isPurchasing {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
        } else {
          Text(primaryCTATitle)
            .font(.tidexHeadline)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
      }
      .foregroundColor(.tidexTextOnBrand)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 52)
      .background(primaryCTAIsEnabled ? Color.tidexBrandPrimary : Color.tidexTextMuted)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!primaryCTAIsEnabled)
  }

  private var cancellationLine: some View {
    Text(.paywallCancelAnytime)
      .font(.tidexFootnote)
      .foregroundColor(Color.tidexTextMuted)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private var bottomCTA: some View {
    VStack(spacing: Spacing.xs) {
      primaryCTA
      cancellationLine
    }
    .padding(.horizontal, Spacing.md)
    .padding(.top, Spacing.lg)
    .padding(.bottom, Spacing.xs)
    .background(
      LinearGradient(
        stops: [
          .init(color: Color.tidexSurfacePrimary.opacity(0), location: 0),
          .init(color: Color.tidexSurfacePrimary.opacity(0.98), location: 0.22),
          .init(color: Color.tidexSurfacePrimary, location: 0.38),
          .init(color: Color.tidexSurfacePrimary, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
    )
  }

  @ViewBuilder
  private var priceLineView: some View {
    if let product = viewModel.proProduct, viewModel.offersFreeTrial {
      let renewal = compactRenewalText(for: product)
      let freePrefix =
        "\(trialDurationDaysText(days: viewModel.trialDurationDays)) \(String(localized: .paywallTrialFreeWord))"

      Text(
        styledTrialPriceLine(
          freePrefix: freePrefix,
          suffix: String(localized: .paywallTrialPriceLineSuffix(renewal))
        )
      )
      .fixedSize(horizontal: false, vertical: true)
    } else {
      Text(priceLine)
        .font(.tidexSubheadline)
        .foregroundColor(Color.tidexTextPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func styledTrialPriceLine(freePrefix: String, suffix: String) -> AttributedString {
    var text = AttributedString(freePrefix + suffix)
    text.font = .tidexSubheadline
    text.foregroundColor = .tidexTextPrimary

    if let range = text.range(of: freePrefix) {
      text[range].font = .tidexSubheadline.weight(.bold)
    }

    return text
  }

  private var restorePurchasesButton: some View {
    Button(action: { onRestorePurchases?() }) {
      Text(.paywallRestorePurchases)
        .font(.tidexLabel)
        .foregroundColor(.tidexBlue)
    }
    .disabled(viewModel.isLoading)
  }

  private func paywallErrorView(_ message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexError)

      Text(message)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexError)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  private var closeButton: some View {
    Button(action: { dismiss() }) {
      Image(systemName: "xmark")
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.tidexTextSecondary)
        .frame(width: 46, height: 46)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(Circle())
        .contentShape(Circle())
    }
    .padding(.top, 106)
    .padding(.trailing, Spacing.lg)
    .accessibilityLabel(Text(.paywallClose))
  }

  private var dividerWithOr: some View {
    HStack(spacing: Spacing.md) {
      Rectangle()
        .fill(Color.tidexBorder.opacity(0.5))
        .frame(height: 1)

      Text(.monthLimitOr)
        .font(.tidexCaptionStrong)
        .foregroundStyle(Color.tidexTextMuted)
        .textCase(.uppercase)
        .tracking(0.5)

      Rectangle()
        .fill(Color.tidexBorder.opacity(0.5))
        .frame(height: 1)
    }
  }

  @ViewBuilder
  private var legalLinks: some View {
    if let termsURL, let privacyURL {
      HStack(spacing: Spacing.md) {
        Link(String(localized: .paywallTermsOfUse), destination: termsURL)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)

        Text("•")
          .foregroundColor(.tidexTextMuted)

        Link(String(localized: .paywallPrivacyPolicy), destination: privacyURL)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  private var termsURL: URL? {
    URL(string: "https://tidex.no/\(Locale.current.urlLanguageCode)/terms")
  }

  private var privacyURL: URL? {
    URL(string: "https://tidex.no/\(Locale.current.urlLanguageCode)/privacy")
  }

  private var heroSeasonTitle: String {
    "\(heroSeasonName(for: currentMonthIndex)) \(currentYear)"
  }

  private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
  }

  private var currentMonthIndex: Int {
    Calendar.current.component(.month, from: Date()) - 1
  }

  private func heroSeasonName(for monthIndex: Int) -> String {
    switch monthIndex {
    case 2...4:
      return String(localized: .monthLimitHeroSeasonSpring)

    case 5...7:
      return String(localized: .monthLimitHeroSeasonSummer)

    case 8...10:
      return String(localized: .monthLimitHeroSeasonAutumn)

    default:
      return String(localized: .monthLimitHeroSeasonWinter)
    }
  }

  private func isHighlightedHeroMonth(_ index: Int) -> Bool {
    ((index - currentMonthIndex + 12) % 12) < 3
  }

  private func shouldShowHeroMonthLabel(_ index: Int) -> Bool {
    index == 0 || index == currentMonthIndex || index == 11
  }

  private func heroMonthLabel(for index: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    return formatter.shortMonthSymbols[index].uppercased()
  }

  private var isCurrentPlan: Bool {
    viewModel.currentTier >= .pro
  }

  private var primaryCTAIsEnabled: Bool {
    viewModel.proProduct != nil && viewModel.trialOffer != .checking && !viewModel.isPurchasing
      && !isCurrentPlan && !isAlternativeBusy
  }

  private var primaryCTATitle: String {
    if isCurrentPlan {
      return String(localized: .paywallCtaCurrentPlan)
    }

    guard viewModel.proProduct != nil, viewModel.trialOffer != .checking else {
      return String(localized: .paywallLoadingButton)
    }

    if viewModel.offersFreeTrial {
      return String(localized: .paywallCtaFreeTrial)
    }

    return String(localized: .paywallCtaSubscribe(String(localized: .paywallPlanProBadge)))
  }

  private var priceLine: String {
    guard let product = viewModel.proProduct, viewModel.trialOffer != .checking else {
      return String(localized: .paywallLoading)
    }

    let renewal = "\(product.displayPrice) \(periodLabel)"

    if viewModel.offersFreeTrial {
      return String(
        localized: .paywallTrialPriceLine(
          trialDurationDaysText(days: viewModel.trialDurationDays),
          compactRenewalText(for: product)
        )
      )
    }

    return String(localized: .paywallSubscribePriceLine(renewal))
  }

  private var periodLabel: String {
    viewModel.billingPeriod == .yearly
      ? String(localized: .paywallPerYear)
      : String(localized: .paywallPerMonth)
  }

  private var compactPeriodLabel: String {
    viewModel.billingPeriod == .yearly
      ? String(localized: .paywallPerYearCompact)
      : String(localized: .paywallPerMonthCompact)
  }

  private var timelineItems: [TrialPaywallTimelineItem] {
    if viewModel.offersFreeTrial {
      return [
        TrialPaywallTimelineItem(
          id: "today",
          title: String(localized: .paywallTimelineToday),
          body: String(localized: .paywallTimelineTodayBody),
          icon: "lock.open.fill",
          isActive: true
        ),
        TrialPaywallTimelineItem(
          id: "reminder",
          title: String(localized: .paywallTimelineDay(Int32(viewModel.trialReminderDay))),
          body: String(localized: .paywallTimelineReminderBody),
          icon: "bell",
          isActive: false
        ),
        TrialPaywallTimelineItem(
          id: "charge",
          title: String(localized: .paywallTimelineDay(Int32(viewModel.trialDurationDays))),
          body: String(localized: .paywallTimelineChargeBody),
          icon: "star",
          isActive: false
        ),
      ]
    }

    return [
      TrialPaywallTimelineItem(
        id: "today",
        title: String(localized: .paywallTimelineToday),
        body: String(localized: .paywallTimelineTodayBody),
        icon: "lock.open.fill",
        isActive: true
      ),
      TrialPaywallTimelineItem(
        id: "manage",
        title: String(localized: .paywallTimelineManage),
        body: String(localized: .paywallTimelineManageBody),
        icon: "gearshape",
        isActive: false
      ),
      TrialPaywallTimelineItem(
        id: "renewal",
        title: String(localized: .paywallTimelineRenewal),
        body: String(localized: .paywallTimelineRenewalBody),
        icon: "calendar",
        isActive: false
      ),
    ]
  }

  private func trialDurationDaysText(days: Int) -> String {
    String(localized: .paywallTrialDurationDays(Int32(days)))
  }

  private func compactRenewalText(for product: Product) -> String {
    "\(compactDisplayPrice(for: product))\(compactPeriodLabel)"
  }

  private func compactDisplayPrice(for product: Product) -> String {
    var price = product.price
    var rounded = Decimal()
    NSDecimalRound(&rounded, &price, 0, .plain)

    if rounded == product.price {
      return product.price.formatted(product.priceFormatStyle.precision(.fractionLength(0)))
    }

    return product.displayPrice
  }

  private func startPurchase() {
    guard let product = viewModel.proProduct, primaryCTAIsEnabled else { return }
    onStartSubscription(product)
  }
}

private struct TrialPaywallTimelineItem: Identifiable {
  let id: String
  let title: String
  let body: String
  let icon: String
  let isActive: Bool
}
