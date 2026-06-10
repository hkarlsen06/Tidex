import SwiftUI

/// Card showing progress towards monthly earnings goal
/// Displays a progress bar with gradient fill
struct MonthlyGoalCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order
  let goal: MonthlyGoal  // swiftlint:disable:this explicit_acl
  var onTap: (() -> Void)?  // swiftlint:disable:this explicit_acl

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface

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

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this accessibility_trait_for_button
      // Header row with title and settings icon
      HStack {
        Text(.statsMonthlyGoalTitle)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Image(systemName: "gearshape")  // swiftlint:disable:this accessibility_label_for_image
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
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
    .contentShape(Rectangle())
    .onTapGesture {
      onTap?()
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private var progressBar: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Background track
        RoundedRectangle(cornerRadius: CornerRadius.xs)
          .fill(Color.tidexSurfaceSecondary)
          .frame(height: 12)  // swiftlint:disable:this no_magic_numbers

        // Progress fill with gradient
        RoundedRectangle(cornerRadius: CornerRadius.xs)
          .fill(progressGradient)
          .frame(
            width: max(0, geometry.size.width * (clampedPercentage / 100)),
            height: 12  // swiftlint:disable:this no_magic_numbers
          )
          .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: clampedPercentage)  // swiftlint:disable:this line_length no_magic_numbers
      }
    }
    .frame(height: 12)  // swiftlint:disable:this no_magic_numbers
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
struct MonthlyGoalEmptyCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  var onTap: (() -> Void)?  // swiftlint:disable:this explicit_acl

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(alignment: .leading, spacing: Spacing.sm) {  // swiftlint:disable:this accessibility_trait_for_button
      HStack {
        Text(.statsMonthlyGoalTitle)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Image(systemName: "gearshape")  // swiftlint:disable:this accessibility_label_for_image
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
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
    .contentShape(Rectangle())
    .onTapGesture {
      onTap?()
    }
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    // In progress
    MonthlyGoalCard(
      goal: MonthlyGoal(
        enabled: true,
        target: 15_000,
        progress: 12_808,
        percentage: 85.4,
        remaining: 2_192
      ),
      onTap: nil
    )

    // Goal reached
    MonthlyGoalCard(
      goal: MonthlyGoal(
        enabled: true,
        target: 15_000,
        progress: 17_500,
        percentage: 116.7,
        remaining: 0
      ),
      onTap: nil
    )

    // Not enabled
    MonthlyGoalEmptyCard(onTap: nil)
  }
  .padding()
  .background(Color.tidexBackground)
}
