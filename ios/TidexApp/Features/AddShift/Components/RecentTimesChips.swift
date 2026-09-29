import SwiftUI

/// Spacing between chips
private let chipSpacing: CGFloat = CornerRadius.sm

/// A time range combination with its usage count
struct TimeRangeCount: Identifiable, Hashable {
  var id: String { "\(startTime)-\(endTime)" }
  let startTime: String
  let endTime: String
  let count: Int

  var displayLabel: String { "\(startTime)-\(endTime)" }
}

/// Maximum number of time range chips to display
private let maxChipCount = 5

/// Horizontal scrollable chips showing frequently used time range combinations
/// Chips are sorted by popularity (most used on the left)
struct RecentTimesChips: View {
  @ScaledMetric(relativeTo: .caption) private var chipBarHeight: CGFloat = 44
  /// Callback when user taps a time range chip
  let onSelect: (TimeRangeCount) -> Void

  /// ID of the currently active time range (matches TimeRangeCount.id)
  var activeRangeId: String?

  /// Optional fixed ranges for demo/preview contexts.
  /// When provided, repository loading is bypassed.
  var presetRanges: [TimeRangeCount]?  // swiftlint:disable:this discouraged_optional_collection explicit_acl

  /// Shifts repository for querying shift data
  private let shiftsRepository = ShiftsRepository.shared

  /// Computed time range counts from shifts
  @State private var timeRangeCounts: [TimeRangeCount] = []

  /// Chips to display, sorted by popularity
  private var visibleRanges: [TimeRangeCount] {
    Array(timeRangeCounts.prefix(maxChipCount))
  }

  var body: some View {
    Group {
      if visibleRanges.isEmpty {
        Color.clear
          .frame(height: chipBarHeight)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: chipSpacing) {
            ForEach(visibleRanges) { range in
              RecentTimeChip(
                range: range, isSelected: range.id == activeRangeId, height: chipBarHeight
              ) {
                onSelect(range)
              }
            }
          }
        }
        .frame(height: chipBarHeight)
      }
    }
    .onAppear {
      loadTimeRangeCountsIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
      loadTimeRangeCountsIfNeeded()
    }
  }

  private func loadTimeRangeCountsIfNeeded() {
    if let presetRanges {
      timeRangeCounts = presetRanges.sorted { lhs, rhs in
        if lhs.count == rhs.count {
          return lhs.id < rhs.id
        }
        return lhs.count > rhs.count
      }
      return
    }

    loadTimeRangeCounts()
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
  let isSelected: Bool
  let height: CGFloat
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
        .font(.tidexMonoCaption)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundColor(isSelected ? .tidexTextOnBrand : .tidexBlueText)
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(isSelected ? Color.tidexBlue : Color.tidexBlue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        .frame(minHeight: height)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(
        verbatim: CalendarGridHelper.shiftTimesAccessibilityText(
          startTime: range.startTime, endTime: range.endTime))
    )
    .accessibilityInputLabels([Text(verbatim: timeRangeText)])
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    RecentTimesChips(
      onSelect: { range in
        print("Selected: \(range.displayLabel)")
      }
    )
    .padding(.horizontal, Spacing.md)
    .background(Color.tidexBackground)
  }
}
