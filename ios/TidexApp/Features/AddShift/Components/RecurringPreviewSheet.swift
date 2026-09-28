import SwiftUI

/// Sheet showing preview of all projected recurring shifts before confirmation
struct RecurringPreviewSheet: View {
  var viewModel: AddShiftViewModel
  @Environment(\.dismiss) private var dismiss

  /// Whether the pattern is indefinite (endless)
  private var isIndefinite: Bool {
    viewModel.endCondition == nil
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.tidexBackground.ignoresSafeArea()

        VStack(spacing: 0) {
          // Summary header
          SummaryHeader(
            totalCount: viewModel.cachedProjectedDates.count,
            conflictCount: viewModel.cachedConflictDates.count,
            startTime: viewModel.startTimeString,
            endTime: viewModel.endTimeString,
            isIndefinite: isIndefinite
          )

          // Scrollable list of projected dates
          ScrollView {
            LazyVStack(spacing: Spacing.xs) {
              ForEach(Array(viewModel.cachedProjectedDates.prefix(50).enumerated()), id: \.offset) {
                _, dateISO in
                ProjectedShiftRow(
                  dateISO: dateISO,
                  startTime: viewModel.startTimeString,
                  endTime: viewModel.endTimeString,
                  hasConflict: viewModel.cachedConflictDates.contains(dateISO)
                )
              }

              if viewModel.cachedProjectedDates.count > 50 {
                MoreShiftsIndicator(
                  remainingCount: viewModel.cachedProjectedDates.count - 50,
                  isIndefinite: isIndefinite
                )
              }
            }
            .padding()
          }

          // Action buttons
          ActionButtons(
            isLoading: viewModel.isLoading,
            onCancel: { dismiss() },
            onConfirm: {
              Task {
                await viewModel.submitRecurringShift()
              }
            }
          )
        }

        // Error display
        if let error = viewModel.error {
          VStack {
            Spacer()
            ErrorBanner(message: error)
              .padding()
          }
        }
      }
      .navigationTitle(String(localized: .previewTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color.tidexBackground, for: .navigationBar)
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}

// MARK: - Summary Header

private struct SummaryHeader: View {
  let totalCount: Int
  let conflictCount: Int
  let startTime: String
  let endTime: String
  let isIndefinite: Bool

  @Environment(\.layoutDirection) private var layoutDirection

  /// Title text - shows "Recurring Shifts" for indefinite, count for limited
  private var titleText: String {
    if isIndefinite {
      return String(localized: .previewOngoingShifts)
    }
    return String(localized: .previewShiftsCount(totalCount))
  }

  /// Subtitle text - shows "Repeats indefinitely" for indefinite, time for limited
  private var subtitleText: String {
    let timeRange = ShiftCardFormatter.localizedTimeRange(
      start: startTime,
      end: endTime,
      locale: Locale.appLocale,
      separator: " - "
    )
    if isIndefinite {
      return "\(timeRange) · " + String(localized: .previewOngoingHint)
    }
    return timeRange
  }

  var body: some View {
    VStack(spacing: Spacing.sm) {
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          HStack(spacing: Spacing.xs) {
            Text(titleText)
              .font(.tidexLargeTitle)
              .foregroundColor(.tidexTextPrimary)

            if isIndefinite {
              Image(systemName: "infinity")
                .font(.tidexHeadline)
                .foregroundColor(.tidexBlue)
            }
          }

          Text(subtitleText)
            .font(.tidexBody)
            .foregroundColor(.tidexTextSecondary)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer()

        if conflictCount > 0 {
          ConflictBadge(count: conflictCount)
        }
      }

      if conflictCount > 0 {
        ConflictWarning(count: conflictCount)
      }
    }
    .padding()
    .background(Color.tidexSurfacePrimary)
  }
}

// MARK: - Conflict Badge

private struct ConflictBadge: View {
  let count: Int

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexCaptionRegular)

      Text(String(localized: .previewConflictBadge(count)))
        .font(.tidexLabelStrong)
    }
    .foregroundColor(.tidexTextOnWarning)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xxxs)
    .background(Color.tidexWarning)
    .clipShape(Capsule())
  }
}

// MARK: - Conflict Warning

private struct ConflictWarning: View {
  let count: Int

  private var warningText: String {
    String(localized: .previewConflictWarningPlural(count))
  }

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundColor(.tidexWarning)

      Text(warningText)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .padding(Spacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexWarning.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
  }
}

// MARK: - Projected Shift Row

private struct ProjectedShiftRow: View {
  let dateISO: String
  let startTime: String
  let endTime: String
  let hasConflict: Bool

  @Environment(\.layoutDirection) private var layoutDirection

  private var formattedDate: String {
    guard let date = Date.fromISODateString(dateISO) else { return dateISO }
    return date.formatted(
      .dateTime.weekday(.wide).day().month(.wide).year().locale(.appLocale)
    ).sentenceCased()
  }

  private var timeRangeText: String {
    ShiftCardFormatter.localizedTimeRange(
      start: startTime,
      end: endTime,
      locale: Locale.appLocale,
      separator: " - "
    )
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(formattedDate)
          .font(.tidexBodyMedium)
          .foregroundColor(hasConflict ? .tidexTextMuted : .tidexTextPrimary)
          .strikethrough(hasConflict)

        Text(timeRangeText)
          .font(.tidexSubheadline)
          .foregroundColor(hasConflict ? .tidexTextMuted : .tidexTextSecondary)
          .strikethrough(hasConflict)
          .environment(\.layoutDirection, .leftToRight)
      }

      Spacer()

      if hasConflict {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.tidexWarning)
      } else {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.tidexSuccess)
      }
    }
    .padding(Spacing.md)
    .background(hasConflict ? Color.tidexWarning.opacity(0.05) : Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .opacity(hasConflict ? 0.6 : 1.0)
  }
}

// MARK: - More Shifts Indicator

private struct MoreShiftsIndicator: View {
  let remainingCount: Int
  let isIndefinite: Bool

  private var displayText: String {
    if isIndefinite {
      return String(localized: .previewContinuesIndefinitely)
    }
    return String(localized: .previewMoreShifts(remainingCount))
  }

  var body: some View {
    HStack(spacing: Spacing.xs) {
      if isIndefinite {
        Image(systemName: "infinity")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexBlue)
      }

      Text(displayText)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

// MARK: - Action Buttons

private struct ActionButtons: View {
  let isLoading: Bool
  let onCancel: () -> Void
  let onConfirm: () -> Void

  var body: some View {
    HStack(spacing: Spacing.md) {
      // Cancel button
      Button(action: onCancel) {
        Text(.previewCancel)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.md)
      }
      .disabled(isLoading)

      // Confirm button
      Button(action: onConfirm) {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        } else {
          Text(.previewConfirm)
            .font(.tidexButton)
            .foregroundColor(.tidexTextOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        }
      }
      .background(Color.tidexBlue)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .disabled(isLoading)
    }
    .padding()
    .background(Color.tidexSurfacePrimary)
  }
}

// MARK: - Preview

#Preview {
  RecurringPreviewSheet(viewModel: AddShiftViewModel())
}
