import SwiftUI

/// Card showing progress towards monthly earnings goal
/// Displays a progress bar with gradient fill
struct MonthlyGoalCard: View {
  let goal: MonthlyGoal

  @Environment(\.userCurrency) private var currency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // MARK: - Computed Properties

  /// Clamped progress percentage (0-100)
  private var clampedPercentage: Double {
    min(max(goal.percentage, 0), 100)
  }

  /// Whether goal has been reached
  private var goalReached: Bool {
    goal.progress >= goal.target
  }

  /// Amount over target (if any)
  private var overAmount: Double {
    max(goal.progress - goal.target, 0)
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Header row with title and settings icon
      HStack {
        Text(.statsMonthlyGoalTitle)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Image(systemName: "gearshape")
          .font(.tidexBody)
          .foregroundColor(.tidexTextMuted)
      }

      // Goal target display
      HStack(spacing: Spacing.xxs) {
        Text("\(String(localized: .statsMonthlyGoalGoalLabel)):")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)

        Text(formatCurrency(goal.target))
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
      }

      // Progress bar
      progressBar

      // Status text (remaining or over target)
      statusText
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(24)
    .tidexCardShadow()
  }

  // MARK: - Subviews

  @ViewBuilder
  private var progressBar: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Background track
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.tidexSurfaceSecondary)
          .frame(height: 12)

        // Progress fill with gradient
        RoundedRectangle(cornerRadius: 6)
          .fill(progressGradient)
          .frame(
            width: max(0, geometry.size.width * (clampedPercentage / 100)),
            height: 12
          )
          .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: clampedPercentage)
      }
    }
    .frame(height: 12)
  }

  private var progressGradient: LinearGradient {
    LinearGradient(
      colors: goalReached ? [.tidexSuccess, .tidexBlue] : [.tidexSuccess, .tidexBlue],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  @ViewBuilder
  private var statusText: some View {
    if goalReached {
      if overAmount > 0 {
        // Over target
        Text(String(localized: .statsMonthlyGoalOverTarget(formatCurrency(overAmount))))
          .font(.tidexSubheadline)
          .foregroundColor(.tidexSuccess)
      } else {
        // Exactly at goal
        Text(.statsMonthlyGoalGoalReached)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexSuccess)
      }
    } else {
      // Still working towards goal
      Text(String(localized: .statsMonthlyGoalRemaining(formatCurrency(goal.remaining))))
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }
}

/// Empty state for when monthly goal is not enabled
struct MonthlyGoalEmptyCard: View {

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        Text(.statsMonthlyGoalTitle)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Image(systemName: "gearshape")
          .font(.tidexBody)
          .foregroundColor(.tidexTextMuted)
      }

      Text(.statsMonthlyGoalNotEnabled)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.mlg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(24)
    .tidexCardShadow()
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    // In progress
    MonthlyGoalCard(
      goal: MonthlyGoal(
        enabled: true,
        target: 15000,
        progress: 12808,
        percentage: 85.4,
        remaining: 2192
      )
    )

    // Goal reached
    MonthlyGoalCard(
      goal: MonthlyGoal(
        enabled: true,
        target: 15000,
        progress: 17500,
        percentage: 116.7,
        remaining: 0
      )
    )

    // Not enabled
    MonthlyGoalEmptyCard()
  }
  .padding()
  .background(Color.tidexBackground)
}
