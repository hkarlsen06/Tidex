import SwiftUI
import StoreKit

// MARK: - Plan Card

/// Card displaying a subscription plan with price and features
struct PlanCard: View {
    let tier: SubscriptionTier
    let product: Product?
    let isCurrentPlan: Bool
    let isPurchasing: Bool
    let onSubscribe: () -> Void

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with tier name and badge
            HStack {
                tierIcon
                    .font(.system(size: 24))
                    .foregroundColor(tierColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tierName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.tidexTextPrimary)

                    if isCurrentPlan {
                        Text("Current Plan")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.tidexSuccess)
                    }
                }

                Spacer()

                if let product = product {
                    priceView(for: product)
                }
            }

            // Features list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexSuccess)

                        Text(feature)
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextSecondary)
                    }
                }
            }

            // Subscribe button
            if !isCurrentPlan {
                Button(action: onSubscribe) {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(product != nil ? "Subscribe" : "Loading...")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 48)
                .foregroundColor(.white)
                .background(product != nil ? tierColor : Color.tidexTextMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(product == nil || isPurchasing)
            }
        }
        .padding(20)
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isCurrentPlan ? tierColor.opacity(0.5) : Color.clear,
                    lineWidth: 2
                )
        )
    }

    // MARK: - Computed Properties

    private var tierName: String {
        switch tier {
        case .pro: return "Pro"
        case .max: return "Max"
        case .free: return "Free"
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

    private var features: [String] {
        switch tier {
        case .pro:
            return [
                "Unlimited months",
                "Advanced statistics",
                "Export to PDF/CSV",
                "Priority support"
            ]
        case .max:
            return [
                "Everything in Pro",
                "Wagey AI Assistant",
                "Recurring shifts",
                "Shift sharing",
                "Premium themes"
            ]
        case .free:
            return [
                "One month of shifts",
                "Basic statistics"
            ]
        }
    }

    @ViewBuilder
    private func priceView(for product: Product) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(product.displayPrice)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.tidexTextPrimary)

            Text(periodLabel(for: product))
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    private func periodLabel(for product: Product) -> String {
        // Determine period from product ID
        if product.id.contains(".year") {
            return "per year"
        } else {
            return "per month"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
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
