import SwiftUI

/// Fixed height for the recent times chips area
private let recentTimesChipBarHeight: CGFloat = 36

/// Estimated width per chip (label + padding)
/// "09:00-17:00" = ~90pt + padding = ~110pt per chip
private let estimatedChipWidth: CGFloat = 110

/// Spacing between chips
private let chipSpacing: CGFloat = 8

/// A time range combination with its usage count
struct TimeRangeCount: Identifiable, Hashable {
    var id: String { "\(startTime)-\(endTime)" }
    let startTime: String
    let endTime: String
    let count: Int

    var displayLabel: String { "\(startTime)-\(endTime)" }
}

/// Horizontal chips showing frequently used time range combinations
/// Chips are sorted by popularity (most used on the left)
/// Only shows chips that fit within the available width
struct RecentTimesChips: View {
    /// Callback when user taps a time range chip
    let onSelect: (TimeRangeCount) -> Void

    /// Available width for laying out chips (passed from parent)
    let availableWidth: CGFloat

    /// Shifts repository for querying shift data
    private let shiftsRepository = ShiftsRepository.shared

    /// Computed time range counts from shifts
    @State private var timeRangeCounts: [TimeRangeCount] = []

    /// Number of chips that can fit in the available width
    private var maxVisibleChips: Int {
        guard availableWidth > 0 else { return 0 }
        // Calculate how many chips fit with spacing
        let chipsCount = Int((availableWidth + chipSpacing) / (estimatedChipWidth + chipSpacing))
        return max(0, chipsCount)
    }

    /// Chips to display, limited by available width
    /// Sorted with most popular on the left
    private var visibleRanges: [TimeRangeCount] {
        // Take only what fits, most popular first (on the left)
        Array(timeRangeCounts.prefix(maxVisibleChips))
    }

    var body: some View {
        Group {
            if visibleRanges.isEmpty {
                // Empty state - just reserve the space
                Color.clear
                    .frame(height: recentTimesChipBarHeight)
            } else {
                HStack(spacing: chipSpacing) {
                    ForEach(visibleRanges) { range in
                        RecentTimeChip(range: range) {
                            onSelect(range)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: recentTimesChipBarHeight)
            }
        }
        .onAppear {
            loadTimeRangeCounts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
            loadTimeRangeCounts()
        }
    }

    /// Count time range combinations from all user shifts
    private func loadTimeRangeCounts() {
        guard let userId = AppCoordinator.shared.getCurrentUserId() else {
            timeRangeCounts = []
            return
        }

        let shifts = shiftsRepository.getAllShifts(for: userId)

        // Count occurrences of each start-end time combination
        var counts: [String: (startTime: String, endTime: String, count: Int)] = [:]

        for shift in shifts {
            let key = "\(shift.start_time)-\(shift.end_time)"
            if let existing = counts[key] {
                counts[key] = (shift.start_time, shift.end_time, existing.count + 1)
            } else {
                counts[key] = (shift.start_time, shift.end_time, 1)
            }
        }

        // Convert to array and sort by count (most used first)
        timeRangeCounts = counts.values
            .map { TimeRangeCount(startTime: $0.startTime, endTime: $0.endTime, count: $0.count) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - Recent Time Chip

private struct RecentTimeChip: View {
    let range: TimeRangeCount
    let onTap: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    private var timeRangeText: String {
        ShiftCardFormatter.localizedTimeRange(
            start: range.startTime,
            end: range.endTime,
            locale: Locale.appLocale,
            separator: "-"
        )
    }

    var body: some View {
        Button(action: onTap) {
            Text(timeRangeText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.tidexBlue)
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.tidexBlue.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        RecentTimesChips(
            onSelect: { range in
                print("Selected: \(range.displayLabel)")
            },
            availableWidth: 350
        )
        .padding(.horizontal, 16)
        .background(Color.tidexBackground)
    }
}
