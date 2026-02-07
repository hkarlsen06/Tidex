import SwiftUI

/// Time period for empty state messaging
enum MonthPeriod {
  case past
  case current
  case future
}

/// Empty state view when there are no shifts for the displayed month
struct ShiftsEmptyState: View {
  /// Whether this is showing for the current month (vs a past/future month)
  let isCurrentMonth: Bool
  /// The month period for more specific messaging
  let monthPeriod: MonthPeriod
  /// Display month name for context
  let monthName: String?
  /// Callback when user taps "Add Shift" button
  let onAddShift: () -> Void

  // Convenience init for backward compatibility
  init(isCurrentMonth: Bool, onAddShift: @escaping () -> Void) {
    self.isCurrentMonth = isCurrentMonth
    self.monthPeriod = isCurrentMonth ? .current : .past
    self.monthName = nil
    self.onAddShift = onAddShift
  }

  // Full init with period
  init(
    isCurrentMonth: Bool, monthPeriod: MonthPeriod, monthName: String?,
    onAddShift: @escaping () -> Void
  ) {
    self.isCurrentMonth = isCurrentMonth
    self.monthPeriod = monthPeriod
    self.monthName = monthName
    self.onAddShift = onAddShift
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: Spacing.mlg) {
      Spacer()

      // Icon - changes based on period
      Image(systemName: iconName)
        .font(.system(size: 56, weight: .light))
        .foregroundColor(iconColor.opacity(0.6))

      // Title
      Text(title)
        .font(.tidexTitle2)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)

      // Subtitle - context-aware message
      Text(subtitle)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.xxl)

      // Action buttons based on period
      actionButtons
        .padding(.top, Spacing.xs)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Computed Properties

  private var iconName: String {
    switch monthPeriod {
    case .past:
      return "clock.arrow.circlepath"
    case .current:
      return "calendar.badge.plus"
    case .future:
      return "calendar.badge.clock"
    }
  }

  private var iconColor: Color {
    switch monthPeriod {
    case .past:
      return .tidexTextMuted
    case .current:
      return .tidexBlue
    case .future:
      return .tidexBlue
    }
  }

  private var title: String {
    switch monthPeriod {
    case .past:
      return String(localized: .shiftsEmptyNoShifts)
    case .current:
      return String(localized: .shiftsEmptyNoShiftsThisMonth)
    case .future:
      if let name = monthName {
        return String(localized: .shiftsEmptyNoShiftsInMonth(name))
      }
      return String(localized: .shiftsEmptyNoShiftsPlanned)
    }
  }

  private var subtitle: String {
    switch monthPeriod {
    case .past:
      if let name = monthName {
        return String(localized: .shiftsEmptyNoPastRecords(name.lowercased()))
      }
      return String(localized: .shiftsEmptyNoRecordsMonth)
    case .current:
      return String(localized: .shiftsEmptyStartTracking)
    case .future:
      return String(localized: .shiftsEmptyPlanAhead)
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    switch monthPeriod {
    case .past:
      // No action for past months
      EmptyView()
    case .current, .future:
      Button(action: onAddShift) {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "plus")
            .font(.tidexCaptionStrong)
          Text(.shiftsEmptyAddShift)
            .font(.tidexButton)
        }
        .foregroundColor(.white)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexBlue)
        .cornerRadius(CornerRadius.lg)
      }
    }
  }
}

// MARK: - Preview

#Preview("Current Month") {
  ShiftsEmptyState(
    isCurrentMonth: true,
    monthPeriod: .current,
    monthName: "January"
  ) {
    print("Add shift tapped")
  }
  .background(Color.tidexBackground)
}

#Preview("Past Month") {
  ShiftsEmptyState(
    isCurrentMonth: false,
    monthPeriod: .past,
    monthName: "December"
  ) {
    print("Add shift tapped")
  }
  .background(Color.tidexBackground)
}

#Preview("Future Month") {
  ShiftsEmptyState(
    isCurrentMonth: false,
    monthPeriod: .future,
    monthName: "February"
  ) {
    print("Add shift tapped")
  }
  .background(Color.tidexBackground)
}
