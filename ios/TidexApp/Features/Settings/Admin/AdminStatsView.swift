import Charts
import SwiftUI

/// Usage numbers from across the app. The server groups them into sections, and each item is
/// drawn by its kind, so new numbers only need a server change.
struct AdminStatsView: View {
  @State private var stats: AdminStats?
  @State private var errorMessage: String?

  var body: some View {
    List {
      if let stats {
        ForEach(stats.sections) { section in
          AdminStatsSection(section: section)
        }
      } else if errorMessage == nil {
        ProgressView()
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
      }
    }
    .listSectionSpacing(.compact)
    .tidexListBackground()
    .navigationTitle("Stats")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await load() }
    .task { await load() }
    .adminErrorAlert($errorMessage)
  }

  private func load() async {
    do {
      stats = try await AdminAPI.stats()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

/// One stats section. Tiles that open a section get their own list section on the plain
/// background, so the card with the rest starts below them.
private struct AdminStatsSection: View {
  let section: AdminStats.Section

  var body: some View {
    if case .tiles(let tiles)? = section.items.first?.content {
      Section {
        AdminStatsTiles(tiles: tiles)
      } header: {
        Text(verbatim: section.title)
      }
      let rest: [AdminStats.Item] = Array(section.items.dropFirst())
      if !rest.isEmpty {
        Section {
          rows(rest)
        }
      }
    } else {
      Section {
        rows(section.items)
      } header: {
        Text(verbatim: section.title)
      }
    }
  }

  private func rows(_ items: [AdminStats.Item]) -> some View {
    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
      AdminStatsItemRow(item: item)
    }
    .listRowBackground(Color.tidexSurfacePrimary)
  }
}

/// One item, either in full or as a row that expands.
private struct AdminStatsItemRow: View {
  let item: AdminStats.Item

  var body: some View {
    if item.isCollapsed {
      DisclosureGroup {
        AdminStatsItemContent(content: item.content, title: nil)
      } label: {
        Text(verbatim: item.title ?? "")
          .foregroundStyle(Color.tidexTextPrimary)
      }
    } else {
      AdminStatsItemContent(content: item.content, title: item.title)
    }
  }
}

private struct AdminStatsItemContent: View {
  let content: AdminStats.Item.Content
  let title: String?

  var body: some View {
    switch content {
    case .tiles(let tiles):
      AdminStatsTiles(tiles: tiles)

    case .series(let points):
      AdminStatsWeeklyChart(title: title, points: points)

    case .bars(let rows, let total):
      // A few options that add up to the whole read best as a donut.
      if total == nil, (1...4).contains(rows.count) {
        AdminStatsDonut(title: title, rows: rows)
      } else {
        AdminStatsBars(
          title: title, rows: rows, whole: total ?? rows.reduce(0) { $0 + $1.value },
          tint: .tidexBlue)
      }

    case .funnel(let rows):
      AdminStatsBars(title: title, rows: rows, whole: rows.first?.value ?? 0, tint: .tidexPurple)

    case .list(let rows):
      if let title {
        AdminStatsTitle(text: title)
      }
      ForEach(rows) { row in
        LabeledContent {
          Text(verbatim: row.value)
        } label: {
          Text(verbatim: row.label)
          if let detail = row.detail {
            Text(verbatim: detail)
          }
        }
      }

    case .cohorts(let cohorts):
      AdminStatsCohortChart(title: title, cohorts: cohorts)

    case .unknown:
      EmptyView()
    }
  }
}

// MARK: - Pieces

private struct AdminStatsTitle: View {
  let text: String

  var body: some View {
    Text(verbatim: text)
      .font(.tidexFootnoteStrong)
      .foregroundStyle(Color.tidexTextSecondary)
  }
}

private struct AdminStatsEmpty: View {
  var body: some View {
    Text(verbatim: "No data yet")
      .font(.tidexFootnote)
      .foregroundStyle(Color.tidexTextMuted)
  }
}

/// "43%", or a dash when there is nothing to divide by.
private func adminStatsPercent(_ value: Int, of whole: Int) -> String {
  guard whole > 0 else { return "–" }
  return (Double(value) / Double(whole)).formatted(.percent.precision(.fractionLength(0)))
}

/// Headline numbers, two or three to a row, one to a row at accessibility text sizes.
/// A tile whose value is a share gets a ring.
private struct AdminStatsTiles: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let tiles: [AdminStats.Tile]

  private var columnCount: Int {
    if dynamicTypeSize.isAccessibilitySize { return 1 }
    return tiles.count == 4 ? 2 : min(max(tiles.count, 1), 3)
  }

  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: columnCount),
      spacing: Spacing.xs
    ) {
      ForEach(tiles) { tile in
        tileView(tile)
      }
    }
    .listRowInsets(EdgeInsets())
    .listRowBackground(Color.clear)
  }

  private func tileView(_ tile: AdminStats.Tile) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack(alignment: .center, spacing: Spacing.xxs) {
        Text(verbatim: tile.value)
          .font(.tidexTitle)
          .foregroundStyle(Color.tidexTextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Spacer(minLength: 0)
        if let progress = tile.progress {
          Gauge(value: min(max(progress, 0), 1)) {
            EmptyView()
          }
          .gaugeStyle(.accessoryCircularCapacity)
          .tint(Color.tidexBlue)
          .scaleEffect(0.5)
          .frame(width: 30, height: 30)
          .accessibilityHidden(true)
        }
      }
      Text(verbatim: tile.label)
        .font(.tidexCaptionRegular)
        .foregroundStyle(Color.tidexTextSecondary)
      if let caption = tile.caption {
        Text(verbatim: caption)
          .font(.tidexCaptionRegular)
          .foregroundStyle(Color.tidexTextMuted)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(Spacing.sm)
    .background(Color.tidexSurfacePrimary, in: .rect(cornerRadius: CornerRadius.md))
    .accessibilityElement(children: .combine)
  }
}

/// Weekly counts as bars, with this week's count above the chart.
private struct AdminStatsWeeklyChart: View {
  let title: String?
  let points: [AdminStats.Point]

  var body: some View {
    // Whole-number ticks, so small counts don't get half-step gridlines.
    let top: Int = max(points.map(\.value).max() ?? 0, 1)
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      if let title {
        AdminStatsTitle(text: title)
      }
      Text(verbatim: points.last.map { "\($0.value) this week" } ?? "–")
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextPrimary)
      Chart(points) { point in
        if let week = point.week {
          BarMark(x: .value("Week", week, unit: .weekOfYear), y: .value("Count", point.value))
            .foregroundStyle(Color.tidexBlue)
        }
      }
      .chartYScale(domain: 0...top)
      .chartYAxis {
        AxisMarks(position: .leading, values: Array(Set([0, top / 2, top])).sorted()) { _ in
          AxisGridLine().foregroundStyle(Color.tidexSeparator)
          AxisValueLabel().foregroundStyle(Color.tidexTextSecondary)
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .month)) { _ in
          AxisValueLabel(format: .dateTime.month(.abbreviated))
        }
      }
      .frame(height: 120)
    }
    .padding(.vertical, Spacing.xxs)
  }
}

/// A few options as a donut, with a legend that has each count and share.
private struct AdminStatsDonut: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let title: String?
  let rows: [AdminStats.Row]

  private static let colors: [Color] = [.tidexBlue, .tidexPurple, .tidexSuccess, .tidexWarning]

  var body: some View {
    let sum: Int = rows.reduce(0) { $0 + $1.value }
    let layout: AnyLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
      : AnyLayout(HStackLayout(spacing: Spacing.lg))
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if let title {
        AdminStatsTitle(text: title)
      }
      if sum == 0 {
        AdminStatsEmpty()
      } else {
        layout {
          donut
          legend(sum: sum)
        }
      }
    }
    .padding(.vertical, Spacing.xxs)
  }

  private var donut: some View {
    Chart {
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
        SectorMark(angle: .value("Count", row.value), innerRadius: .ratio(0.62), angularInset: 1.5)
          .foregroundStyle(Self.colors[index % Self.colors.count])
      }
    }
    .frame(width: 88, height: 88)
    .accessibilityHidden(true)
  }

  private func legend(sum: Int) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
        HStack(spacing: Spacing.xs) {
          Circle()
            .fill(Self.colors[index % Self.colors.count])
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
          Text(verbatim: row.label)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextPrimary)
          Spacer(minLength: Spacing.xs)
          Text(verbatim: "\(row.value.formatted()) · \(adminStatsPercent(row.value, of: sum))")
            .font(.tidexFootnote.monospacedDigit())
            .foregroundStyle(Color.tidexTextSecondary)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}

/// Labeled bars with a count and each row's share of `whole`. Rows show even when `whole` is 0,
/// because a funnel can have later steps without the first, for example after resumed setup.
private struct AdminStatsBars: View {
  let title: String?
  let rows: [AdminStats.Row]
  let whole: Int
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if let title {
        AdminStatsTitle(text: title)
      }
      if rows.isEmpty {
        AdminStatsEmpty()
      } else {
        ForEach(rows) { row in
          bar(row)
        }
      }
    }
    .padding(.vertical, Spacing.xxs)
  }

  private func bar(_ row: AdminStats.Row) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxxs) {
      HStack(alignment: .firstTextBaseline) {
        Text(verbatim: row.label)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextPrimary)
        Spacer(minLength: Spacing.xs)
        Text(verbatim: "\(row.value.formatted()) · \(adminStatsPercent(row.value, of: whole))")
          .font(.tidexFootnote.monospacedDigit())
          .foregroundStyle(Color.tidexTextSecondary)
      }
      ProgressView(value: whole > 0 ? min(Double(row.value) / Double(whole), 1) : 0)
        .tint(tint)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
}

/// For each sign-up month, the share of accounts that logged a shift and the share active in
/// the last 30 days. The number of accounts sits under each month.
private struct AdminStatsCohortChart: View {
  let title: String?
  let cohorts: [AdminStats.Cohort]

  private static let logged = "Logged a shift"
  private static let active = "Active now"

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let title {
        AdminStatsTitle(text: title)
      }
      if cohorts.isEmpty {
        AdminStatsEmpty()
      } else {
        chart
      }
    }
    .padding(.vertical, Spacing.xxs)
  }

  private var chart: some View {
    Chart {
      ForEach(cohorts) { cohort in
        bar(cohort, metric: Self.logged, count: cohort.logged)
        bar(cohort, metric: Self.active, count: cohort.active)
      }
    }
    .chartForegroundStyleScale([Self.logged: Color.tidexBlue, Self.active: Color.tidexPurple])
    .chartLegend(position: .top, alignment: .leading)
    .chartYScale(domain: 0...1)
    .chartYAxis {
      AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
        AxisGridLine().foregroundStyle(Color.tidexSeparator)
        AxisValueLabel {
          if let share = value.as(Double.self) {
            Text(share, format: .percent)
          }
        }
        .foregroundStyle(Color.tidexTextSecondary)
      }
    }
    .chartXAxis {
      AxisMarks { value in
        AxisValueLabel {
          if let month = value.as(String.self) {
            VStack(spacing: 0) {
              Text(verbatim: month)
              if let cohort = cohorts.first(where: { $0.label == month }) {
                Text(cohort.total, format: .number)
                  .foregroundStyle(Color.tidexTextMuted)
              }
            }
          }
        }
      }
    }
    .frame(height: 170)
  }

  private func bar(_ cohort: AdminStats.Cohort, metric: String, count: Int) -> some ChartContent {
    BarMark(
      x: .value("Month", cohort.label),
      y: .value("Share", cohort.total > 0 ? Double(count) / Double(cohort.total) : 0)
    )
    .foregroundStyle(by: .value("Measure", metric))
    .position(by: .value("Measure", metric))
  }
}

#Preview {
  NavigationStack {
    AdminStatsView()
  }
}
