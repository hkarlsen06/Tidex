import StoreKit
import SwiftUI

// MARK: - Plan Card

/// Card displaying a subscription plan with price and features
struct PlanCard: View {
  let tier: SubscriptionTier
  let product: Product?
  let isCurrentPlan: Bool
  let isPurchasing: Bool
  let onSubscribe: () -> Void

  /// Local state to provide immediate feedback on tap, preventing double-tap issues
  @State private var isSubscribeTapped = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Header with tier name and badge
      HStack {
        tierIcon
          .font(.system(size: 24))
          .foregroundColor(tierColor)

        VStack(alignment: .leading, spacing: Spacing.micro) {
          // Use App Store Connect localized name if available
          Text(product?.displayName ?? tierName)
            .font(.tidexTitle2)
            .foregroundColor(.tidexTextPrimary)

          if isCurrentPlan {
            Text(.paywallCurrentPlan)
              .font(.tidexCaption)
              .foregroundColor(.tidexSuccess)
          }
        }

        Spacer()

        if let product {
          priceView(for: product)
        }
      }

      // Product description from App Store Connect
      if let product {
        Text(product.description)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      // Subscribe button
      if !isCurrentPlan {
        Button(action: {
          // Set local state immediately for instant feedback (prevents double-tap)
          isSubscribeTapped = true
          onSubscribe()
        }) {
          if isPurchasing || isSubscribeTapped {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .frame(maxWidth: .infinity)
          } else {
            Text(
              product != nil
                ? String(localized: .paywallSubscribe) : String(localized: .paywallLoadingButton)
            )
            .font(.tidexButton)
            .frame(maxWidth: .infinity)
          }
        }
        .frame(height: 48)
        .foregroundColor(.white)
        .background(product != nil ? tierColor : Color.tidexTextMuted)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .disabled(product == nil || isPurchasing || isSubscribeTapped)
        .onChange(of: isPurchasing) { _, newValue in
          // Reset local tap state when purchase state changes
          if !newValue {
            isSubscribeTapped = false
          }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSubscribeTapped)
      }
    }
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .strokeBorder(
          isCurrentPlan ? tierColor.opacity(0.5) : Color.clear,
          lineWidth: 2
        )
    )
    .tidexCardShadow(cornerRadius: CornerRadius.xxl)
  }

  // MARK: - Computed Properties

  private var tierName: String {
    switch tier {
    case .pro: return String(localized: .paywallTierPro)
    case .max: return String(localized: .paywallTierMax)
    case .free: return String(localized: .paywallTierFree)
    }
  }

  private var tierIcon: some View {
    Group {
      switch tier {
      case .pro:
        Image(systemName: "star.fill")

      case .max:
        Image(systemName: "crown.fill")

      case .free:
        Image(systemName: "person.fill")
      }
    }
  }

  private var tierColor: Color {
    switch tier {
    case .pro: return .tidexBlue
    case .max: return .tidexPurple
    case .free: return .tidexTextMuted
    }
  }

  @ViewBuilder
  private func priceView(for product: Product) -> some View {
    VStack(alignment: .trailing, spacing: Spacing.micro) {
      Text(product.displayPrice)
        .font(.tidexPrice)
        .foregroundColor(.tidexTextPrimary)

      Text(periodLabel(for: product))
        .font(.tidexPricePeriod)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private func periodLabel(for product: Product) -> String {
    // Determine period from product ID
    if product.id.contains(".year") {
      return String(localized: .paywallPerYear)
    }
    return String(localized: .paywallPerMonth)
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    PlanCard(
      tier: .pro,
      product: nil,
      isCurrentPlan: false,
      isPurchasing: false,
      onSubscribe: {}
    )

    PlanCard(
      tier: .max,
      product: nil,
      isCurrentPlan: true,
      isPurchasing: false,
      onSubscribe: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
