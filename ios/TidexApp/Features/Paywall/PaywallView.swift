import Foundation
import StoreKit
import SwiftUI

// MARK: - Paywall View

/// Main paywall view showing subscription purchase flow.
struct PaywallView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = PaywallViewModel()

  /// Optional context type about why the paywall is being shown.
  var contextType: PaywallContextType?

  /// Legacy: Optional pre-built context for backward compatibility with previews.
  var context: PaywallContext?

  private var primaryProduct: Product? {
    viewModel.proProduct
  }

  private var hasConfiguredTrial: Bool {
    viewModel.hasConfiguredTrial
  }

  private var isCurrentPlan: Bool {
    viewModel.currentTier >= .pro
  }

  var body: some View {
    paywallContent
      .task {
        await viewModel.loadProducts()
      }
      .onChange(of: viewModel.purchaseSucceeded) { _, succeeded in
        if succeeded {
          dismiss()
        }
      }
      .overlay {
        if viewModel.isLoading, !viewModel.hasProducts {
          loadingOverlay
        }
      }
  }

  @ViewBuilder
  private var paywallContent: some View {
    if contextType == .upgrade {
      upgradePaywall
    } else if contextType == .wageyLimit {
      wageyLimitPaywall
    } else {
      legacyPaywall
    }
  }

  private var upgradePaywall: some View {
    TrialPaywallScaffold(
      viewModel: viewModel,
      showsAlternativeSection: false,
      showsRestorePurchases: true,
      onStartSubscription: { product in
        Task {
          await viewModel.purchase(product)
        }
      },
      onRestorePurchases: {
        Task {
          await viewModel.restorePurchases()
        }
      }
    ) {
      EmptyView()
    }
  }

  private var wageyLimitPaywall: some View {
    TrialPaywallScaffold(
      viewModel: viewModel,
      showsRestorePurchases: true,
      onStartSubscription: { product in
        Task {
          await viewModel.purchase(product)
        }
      },
      onRestorePurchases: {
        Task {
          await viewModel.restorePurchases()
        }
      }
    ) {
      bonusCard
    }
  }

  private var legacyPaywall: some View {
    NavigationStack {
      ZStack(alignment: .topTrailing) {
        Color.tidexBackground
          .ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(spacing: Spacing.lg) {
            paywallCard

            if let error = viewModel.error {
              errorView(error)
            }

            footerActions
          }
          .padding(.horizontal, Spacing.lg)
          .padding(.top, Spacing.xl)
          .padding(.bottom, Spacing.xxl)
        }

        closeButton
      }
      .toolbar(.hidden, for: .navigationBar)
      .background(Color.tidexBackground)
    }
  }

  // MARK: - Main Card

  private var paywallCard: some View {
    VStack(spacing: 0) {
      artworkHeader

      VStack(alignment: .leading, spacing: Spacing.mlg) {
        headlineBlock
        billingSelector
        timeline
        primaryCTA
        cancellationLine
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.top, Spacing.mlg)
      .padding(.bottom, Spacing.lg)
    }
    .background(Color.tidexLightSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 32, style: .continuous)
        .strokeBorder(Color.tidexLightBorderSubtle.opacity(0.55), lineWidth: 1)
    )
    .shadow(color: Color.tidexPurple.opacity(0.16), radius: 26, y: 14)
    .frame(maxWidth: 430)
    .frame(maxWidth: .infinity)
  }

  private var artworkHeader: some View {
    ZStack(alignment: .bottom) {
      LinearGradient(
        colors: [
          Color.tidexBlue.opacity(0.95),
          Color.tidexPurple.opacity(0.95),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      HStack(alignment: .bottom, spacing: Spacing.sm) {
        miniCalendar
        miniPaycheck
        miniExportTile
      }
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.md)
      .padding(.bottom, Spacing.xl)

      LinearGradient(
        colors: [
          Color.tidexLightSurfacePrimary.opacity(0),
          Color.tidexLightSurfacePrimary.opacity(0.94),
          Color.tidexLightSurfacePrimary,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 52)
    }
    .frame(height: 142)
  }

  private var miniCalendar: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text(sampleMonthLabel)
          .font(.tidexCaptionStrong)
        Spacer()
        Image(systemName: "plus")
          .font(.tidexCaptionStrong)
      }

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 5)
      {
        ForEach(0..<12, id: \.self) { index in
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
              index.isMultiple(of: 3) ? Color.tidexBlue.opacity(0.78) : Color.white.opacity(0.62)
            )
            .frame(height: 12)
        }
      }
    }
    .foregroundColor(Color.tidexLightTextPrimary)
    .padding(Spacing.sm)
    .frame(width: 112, height: 92)
    .background(Color.white.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .shadow(color: Color.tidexDarkBackgroundColor.opacity(0.16), radius: 12, y: 6)
  }

  private var miniPaycheck: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(verbatim: "29 430 kr")
        .font(.tidexHeadline)
        .foregroundColor(Color.tidexLightTextPrimary)

      HStack(alignment: .bottom, spacing: 5) {
        ForEach([0.42, 0.72, 0.55, 0.88, 0.64], id: \.self) { value in
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.tidexPurple.opacity(0.72))
            .frame(width: 10, height: 46 * value)
        }
      }
    }
    .padding(Spacing.sm)
    .frame(width: 116, height: 106)
    .background(Color.white.opacity(0.86))
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .shadow(color: Color.tidexDarkBackgroundColor.opacity(0.18), radius: 14, y: 7)
  }

  private var miniExportTile: some View {
    VStack(spacing: Spacing.xs) {
      Image(systemName: "doc.text.fill")
        .font(.system(size: 24, weight: .semibold))
      Text("PDF")
        .font(.tidexCaptionStrong)
    }
    .foregroundColor(Color.tidexLightTextPrimary)
    .frame(width: 70, height: 78)
    .background(Color.white.opacity(0.76))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .shadow(color: Color.tidexDarkBackgroundColor.opacity(0.14), radius: 10, y: 5)
  }

  private var headlineBlock: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(hasConfiguredTrial ? .paywallTrialTitle : .paywallSubscribeTitle)
        .font(.system(size: 30, weight: .bold, design: .default))
        .foregroundColor(Color.tidexLightTextPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(.paywallTrialSubtitle)
        .font(.tidexSubheadline)
        .foregroundColor(Color.tidexLightTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Text(priceLine)
        .font(.tidexSubheadline.weight(.semibold))
        .foregroundColor(Color.tidexLightTextPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Spacing.xxs)
    }
  }

  private var billingSelector: some View {
    HStack(spacing: Spacing.xxs) {
      billingOption(.monthly)
      billingOption(.yearly)
    }
    .padding(Spacing.xxs)
    .background(Color.tidexLightSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
          .foregroundColor(isSelected ? Color.tidexLightTextPrimary : Color.tidexLightTextMuted)

        if period == .yearly,
          let savings = viewModel.yearlySavingsPercent(for: .pro)
        {
          Text(
            String(localized: .paywallSavePercent(FormatterCache.percentagePoints(Double(savings))))
          )
          .font(.tidexMicro.bold())
          .foregroundColor(isSelected ? .tidexBlue : Color.tidexLightTextMuted)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: 50)
      .background(isSelected ? Color.tidexLightSurfacePrimary : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var timeline: some View {
    VStack(spacing: 0) {
      ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
        timelineRow(
          item: item,
          isLast: index == timelineItems.count - 1
        )
      }
    }
    .padding(.top, Spacing.xxs)
  }

  private func timelineRow(item: PaywallTimelineItem, isLast: Bool) -> some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      VStack(spacing: 0) {
        ZStack {
          Circle()
            .fill(item.isActive ? Color.tidexPurple : Color.tidexLightSurfaceSecondary)
            .frame(width: 42, height: 42)

          Image(systemName: item.icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(item.isActive ? .tidexTextOnBrand : Color.tidexLightTextMuted)
        }

        if !isLast {
          Rectangle()
            .fill(item.isActive ? Color.tidexPurple.opacity(0.72) : Color.tidexLightBorderSubtle)
            .frame(width: 3, height: 46)
        }
      }
      .frame(width: 46)

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(item.title)
          .font(.tidexHeadline)
          .foregroundColor(Color.tidexLightTextPrimary)

        Text(item.body)
          .font(.tidexBody)
          .foregroundColor(Color.tidexLightTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, Spacing.xxs)

      Spacer(minLength: 0)
    }
  }

  private var primaryCTA: some View {
    Button(action: purchasePrimaryProduct) {
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
      .frame(height: 58)
      .background(
        LinearGradient(
          colors: [
            primaryCTAIsEnabled ? Color.tidexBlue : Color.tidexLightTextMuted.opacity(0.55),
            primaryCTAIsEnabled ? Color.tidexPurple : Color.tidexLightTextMuted.opacity(0.55),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!primaryCTAIsEnabled)
    .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.isPurchasing)
  }

  private var cancellationLine: some View {
    Text(.paywallCancelAnytime)
      .font(.tidexFootnote)
      .foregroundColor(Color.tidexLightTextMuted)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  // MARK: - Supporting Sections

  private var footerActions: some View {
    VStack(spacing: Spacing.md) {
      Button(action: {
        Task { await viewModel.restorePurchases() }
      }) {
        Text(.paywallRestorePurchases)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
      }
      .disabled(viewModel.isLoading)

      legalLinks
    }
  }

  private var closeButton: some View {
    Button(action: { dismiss() }) {
      Image(systemName: "xmark")
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 46, height: 46)
        .background(Color.white.opacity(0.14))
        .clipShape(Circle())
        .contentShape(Circle())
    }
    .padding(.top, Spacing.lg)
    .padding(.trailing, Spacing.lg)
    .accessibilityLabel(Text(.paywallClose))
  }

  @ViewBuilder
  private func errorView(_ error: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexError)

      Text(error)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)

      Spacer()

      Button(action: { viewModel.clearError() }) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
  }

  private var bonusCard: some View {
    let bonusProduct = viewModel.bonusProduct

    return VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "sparkles")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.tidexBlue)

        Text(bonusProduct?.displayName ?? String(localized: .paywallLoading))
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)

        Spacer()
      }

      if let productDescription = bonusProduct?.description,
        !productDescription.isEmpty
      {
        Text(productDescription)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(action: {
        Task {
          await viewModel.purchaseBonus()
        }
      }) {
        if viewModel.isPurchasing {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
            .frame(maxWidth: .infinity)
        } else if let price = bonusProduct?.displayPrice {
          Text(String(localized: .paywallBonusBuyFor(price)))
            .font(.tidexButton)
            .frame(maxWidth: .infinity)
        } else {
          Text(.paywallLoadingButton)
            .font(.tidexButton)
            .frame(maxWidth: .infinity)
        }
      }
      .frame(height: 48)
      .foregroundColor(.tidexTextOnBrand)
      .background(viewModel.bonusProduct != nil ? Color.tidexBlue : Color.tidexTextMuted)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .disabled(viewModel.bonusProduct == nil || viewModel.isPurchasing)
    }
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .tidexCardShadow(cornerRadius: CornerRadius.xxl)
  }

  // swiftlint:disable force_unwrapping
  private var termsURL: URL {
    URL(string: "https://tidex.no/\(Locale.current.urlLanguageCode)/terms")!
  }

  private var privacyURL: URL {
    URL(string: "https://tidex.no/\(Locale.current.urlLanguageCode)/privacy")!
  }

  private var legalLinks: some View {
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
  // swiftlint:enable force_unwrapping

  private var loadingOverlay: some View {
    ZStack {
      Color.tidexBackground.opacity(0.8)

      VStack(spacing: Spacing.md) {
        ProgressView()
          .scaleEffect(1.2)

        Text(.paywallLoading)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
      }
    }
    .ignoresSafeArea()
  }

  // MARK: - Actions and Derived Copy

  private var primaryCTAIsEnabled: Bool {
    primaryProduct != nil && !viewModel.isPurchasing && !isCurrentPlan
  }

  private var sampleMonthLabel: String {
    Calendar.current.shortMonthSymbols[5].uppercased()
  }

  private var primaryCTATitle: String {
    if isCurrentPlan {
      return String(localized: .paywallCtaCurrentPlan)
    }

    guard primaryProduct != nil else {
      return String(localized: .paywallLoadingButton)
    }

    if hasConfiguredTrial {
      return String(localized: .paywallCtaFreeTrial)
    }

    return String(localized: .paywallCtaSubscribe(String(localized: .paywallPlanProBadge)))
  }

  private var priceLine: String {
    guard let product = primaryProduct else {
      return String(localized: .paywallLoading)
    }

    let renewal = "\(product.displayPrice) \(periodLabel(for: product))"

    if hasConfiguredTrial {
      return String(
        localized: .paywallTrialPriceLine(
          trialDurationText(days: viewModel.trialDurationDays),
          compactRenewalText(for: product)
        )
      )
    }

    return String(localized: .paywallSubscribePriceLine(renewal))
  }

  private var timelineItems: [PaywallTimelineItem] {
    if hasConfiguredTrial {
      return [
        PaywallTimelineItem(
          id: "today",
          title: String(localized: .paywallTimelineToday),
          body: String(localized: .paywallTimelineTodayBody),
          icon: "lock.open.fill",
          isActive: true
        ),
        PaywallTimelineItem(
          id: "reminder",
          title: String(localized: .paywallTimelineDay(Int32(viewModel.trialReminderDay))),
          body: String(localized: .paywallTimelineReminderBody),
          icon: "bell",
          isActive: false
        ),
        PaywallTimelineItem(
          id: "charge",
          title: String(localized: .paywallTimelineDay(Int32(viewModel.trialDurationDays))),
          body: String(localized: .paywallTimelineChargeBody),
          icon: "star",
          isActive: false
        ),
      ]
    }

    return [
      PaywallTimelineItem(
        id: "today",
        title: String(localized: .paywallTimelineToday),
        body: String(localized: .paywallTimelineTodayBody),
        icon: "lock.open.fill",
        isActive: true
      ),
      PaywallTimelineItem(
        id: "manage",
        title: String(localized: .paywallTimelineManage),
        body: String(localized: .paywallTimelineManageBody),
        icon: "gearshape",
        isActive: false
      ),
      PaywallTimelineItem(
        id: "renewal",
        title: String(localized: .paywallTimelineRenewal),
        body: String(localized: .paywallTimelineRenewalBody),
        icon: "calendar",
        isActive: false
      ),
    ]
  }

  private func purchasePrimaryProduct() {
    guard let product = primaryProduct, primaryCTAIsEnabled else { return }

    Task {
      await viewModel.purchase(product)
    }
  }

  private func periodLabel(for product: Product) -> String {
    if product.id.contains(".year") {
      return String(localized: .paywallPerYear)
    }

    return String(localized: .paywallPerMonth)
  }

  private func compactPeriodLabel(for product: Product) -> String {
    if product.id.contains(".year") {
      return String(localized: .paywallPerYearCompact)
    }

    return String(localized: .paywallPerMonthCompact)
  }

  private func trialDurationText(days: Int) -> String {
    return String(localized: .paywallTrialDurationDays(Int32(days)))
  }

  private func compactRenewalText(for product: Product) -> String {
    "\(compactDisplayPrice(for: product))\(compactPeriodLabel(for: product))"
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
}

private struct PaywallTimelineItem: Identifiable {
  let id: String
  let title: String
  let body: String
  let icon: String
  let isActive: Bool
}

// MARK: - Paywall Context

/// Context for why the paywall is being shown.
enum PaywallContextType {
  case monthLimit
  case upgrade
  case wageyLimit

  var icon: String {
    switch self {
    case .monthLimit: return "calendar.badge.exclamationmark"
    case .upgrade: return "crown.fill"
    case .wageyLimit: return "bubble.left.and.exclamationmark.bubble.right"
    }
  }

  var title: String {
    switch self {
    case .monthLimit: return String(localized: .paywallShiftLimitTitle)
    case .upgrade: return String(localized: .paywallUpgradeTitle)
    case .wageyLimit: return String(localized: .paywallWageyLimitTitle)
    }
  }

  var message: String {
    switch self {
    case .monthLimit: return String(localized: .paywallShiftLimitMessage)
    case .upgrade: return String(localized: .paywallUpgradeMessage)
    case .wageyLimit: return String(localized: .paywallWageyLimitMessage)
    }
  }
}

/// Context for why the paywall is being shown.
struct PaywallContext {
  let icon: String
  let title: String
  let message: String

  init(type: PaywallContextType) {
    self.icon = type.icon
    self.title = type.title
    self.message = type.message
  }

  // swiftlint:disable:next explicit_acl explicit_type_interface
  static let monthLimit = Self(
    icon: "calendar.badge.exclamationmark",
    title: "Upgrade to Add More Months",
    message:
      "Free plan allows shifts in one month at a time. Upgrade to track shifts across multiple months."
  )

  // swiftlint:disable:next explicit_acl explicit_type_interface
  static let upgrade = Self(
    icon: "crown.fill",
    title: "Unlock Premium Features",
    message: "Get unlimited months, advanced statistics, Wagey AI, and more."
  )

  // swiftlint:disable:next explicit_acl explicit_type_interface
  static let wageyLimit = Self(
    icon: "bubble.left.and.exclamationmark.bubble.right",
    title: "Message Limit Reached",
    message: "You've used all your messages this month. Upgrade to continue chatting with Wagey."
  )

  private init(icon: String, title: String, message: String) {
    self.icon = icon
    self.title = title
    self.message = message
  }
}

// MARK: - Preview

#Preview {
  PaywallView(context: .monthLimit)
}

#Preview("No Context") {
  PaywallView()
}
