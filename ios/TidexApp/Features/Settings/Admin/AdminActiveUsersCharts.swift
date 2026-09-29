import Charts
import SwiftUI

/// Active users per hour for the last 24 hours, next to active users per day for the last 30 days.
/// Shows empty panels while the data loads.
struct AdminActiveUsersCharts: View {
  let chart: AdminActiveUsersChart?

  var body: some View {
    HStack(spacing: Spacing.xs) {
      let hours: [AdminActiveUsersChart.Bucket] = chart?.hours ?? []
      panel("Last 24 hours", caption: hours.last.map { "\($0.users) this hour" }, buckets: hours) {
        Chart(hours) { bucket in
          if let time = bucket.time {
            BarMark(x: .value("Hour", time, unit: .hour), y: .value("Users", bucket.users))
              .foregroundStyle(Color.tidexBlue)
          }
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
            AxisValueLabel(format: .dateTime.hour())
          }
        }
      }

      let days: [AdminActiveUsersChart.Bucket] = chart?.days ?? []
      panel("Last 30 days", caption: days.last.map { "\($0.users) today" }, buckets: days) {
        Chart(days) { bucket in
          if let time = bucket.time {
            AreaMark(x: .value("Day", time, unit: .day), y: .value("Users", bucket.users))
              .foregroundStyle(Color.tidexPurple.opacity(0.2))
            LineMark(x: .value("Day", time, unit: .day), y: .value("Users", bucket.users))
              .foregroundStyle(Color.tidexPurple)
          }
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .day, count: 10)) { _ in
            AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
          }
        }
      }
    }
  }

  private func panel(
    _ title: String, caption: String?, buckets: [AdminActiveUsersChart.Bucket],
    @ViewBuilder chart: () -> some View
  ) -> some View {
    // Whole-number ticks, so one or two users don't get a 0.5 gridline.
    let top: Int = max(buckets.map(\.users).max() ?? 0, 1)
    return VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(title)
        .font(.tidexCaptionRegular)
        .foregroundStyle(Color.tidexTextSecondary)
      Text(caption ?? "–")
        .font(.tidexFootnoteStrong)
        .foregroundStyle(Color.tidexTextPrimary)
      chart()
        .chartYScale(domain: 0...top)
        .chartYAxis {
          AxisMarks(position: .leading, values: Array(Set([0, top / 2, top])).sorted()) { _ in
            AxisGridLine().foregroundStyle(Color.tidexSeparator)
            AxisValueLabel().foregroundStyle(Color.tidexTextSecondary)
          }
        }
        .frame(height: 110)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.sm)
    .background(Color.tidexSurfacePrimary, in: .rect(cornerRadius: CornerRadius.md))
  }
}
