import SwiftUI

/// Sheet showing preview of all projected recurring shifts before confirmation
struct RecurringPreviewSheet: View {
    @ObservedObject var viewModel: AddShiftViewModel
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
                        LazyVStack(spacing: 8) {
                            ForEach(Array(viewModel.cachedProjectedDates.prefix(50).enumerated()), id: \.offset) { _, dateISO in
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
        } else if totalCount == 1 {
            return String(localized: .previewShiftSingular)
        } else {
            return String(localized: .previewShiftsCount(totalCount))
        }
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
        } else {
            return timeRange
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(titleText)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.tidexTextPrimary)

                        if isIndefinite {
                            Image(systemName: "infinity")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.tidexBlue)
                        }
                    }

                    Text(subtitleText)
                        .font(.system(size: 16))
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
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))

            Text(String(localized: .previewConflictBadge(count)))
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.tidexWarning)
        .clipShape(Capsule())
    }
}

// MARK: - Conflict Warning

private struct ConflictWarning: View {
    let count: Int
    
    private var warningText: String {
        if count == 1 {
            return String(localized: .previewConflictWarningSingular)
        } else {
            return String(localized: .previewConflictWarningPlural(count))
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.tidexWarning)

            Text(warningText)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tidexWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d. MMMM yyyy"  // Full weekday name, e.g. "Mandag, 3. februar 2025"
        formatter.locale = Locale.appLocale
        let formatted = formatter.string(from: date)
        // Capitalize first letter
        return formatted.prefix(1).uppercased() + formatted.dropFirst()
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
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(hasConflict ? .tidexTextMuted : .tidexTextPrimary)
                    .strikethrough(hasConflict)

                Text(timeRangeText)
                    .font(.system(size: 14))
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
        .padding(16)
        .background(hasConflict ? Color.tidexWarning.opacity(0.05) : Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        } else {
            return String(localized: .previewMoreShifts(remainingCount))
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if isIndefinite {
                Image(systemName: "infinity")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexBlue)
            }

            Text(displayText)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextMuted)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Action Buttons

private struct ActionButtons: View {
    let isLoading: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Cancel button
            Button(action: onCancel) {
                Text(.previewCancel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .disabled(isLoading)

            // Confirm button
            Button(action: onConfirm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Text(.previewConfirm)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .background(Color.tidexBlue)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
