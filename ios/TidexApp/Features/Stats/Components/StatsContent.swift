import SwiftUI

/// The Stats drawing for one month or one year. It holds no view model, so the design-review
/// screens render it from fixtures. A new page swaps values in place in one animation. The hero
/// stays the same view in both periods, so switching period rolls its numbers without moving it.
struct StatsContent: View {
  enum Page: Equatable {
    case month(StatsLattice)
    case year(StatsYearLattice)
  }

  let page: Page
  let onSelectMonth: (FocusMonth) -> Void
  var isExporting: Bool = false
  let onExport: () -> Void
  var onScrubbingChange: (Bool) -> Void = { _ in }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsHero(hero: hero, metrics: metrics)
      switch page {
      case .month(let lattice):
        StatsPaceSection(pace: lattice.pace, onScrubbingChange: onScrubbingChange)
          .padding(.top, StatsRhythm.section)
        StatsWeeksSection(weeks: lattice.weeks)
          .padding(.top, StatsRhythm.section)
        StatsYearSection(year: lattice.year) { month in
          onSelectMonth(FocusMonth(year: lattice.year.year, month: month))
        }
        .padding(.top, StatsRhythm.section)
      case .year(let lattice):
        StatsMonthsSection(months: lattice.months) { month in
          onSelectMonth(FocusMonth(year: lattice.year, month: month))
        }
        .padding(.top, StatsRhythm.section)
        StatsYearEmploymentSection(
          employment: lattice.employment, currentMonth: lattice.currentMonth
        )
        .padding(.top, StatsRhythm.section)
      }
      StatsExportRow(period: exportPeriod, isExporting: isExporting, action: onExport)
        .padding(.top, StatsRhythm.section)
    }
    .animation(
      MotionTokens.optionalAnimation(.emphasis, reduceMotion: reduceMotion), value: page)
  }

  private var hero: StatsLattice.Hero {
    switch page {
    case .month(let lattice): lattice.hero
    case .year(let lattice): lattice.hero
    }
  }

  /// What the export row downloads: the month or the year on screen.
  private var exportPeriod: String {
    switch hero.period {
    case .month(let month, _): StatsFormat.monthName(month, withYear: true)
    case .year(let year): String(year)
    }
  }

  private var metrics: StatsLattice.Metrics {
    switch page {
    case .month(let lattice): lattice.metrics
    case .year(let lattice): lattice.metrics
    }
  }
}

extension View {
  /// The width cap and insets around the Stats content, shared by the screen and its
  /// design-review fixtures.
  func statsContentFrame() -> some View {
    frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.horizontal, Spacing.mlg)
      // Clears the sync status pill that floats under the navigation bar.
      .padding(.top, Spacing.xxxl)
      // The screen adds the period and month pickers below this through a safe area inset.
      .padding(.bottom, Spacing.xl)
      .frame(maxWidth: .infinity)
  }
}

private struct StatsExportRow: View {
  let period: String
  let isExporting: Bool
  let action: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.sm) {
        labels
        ZStack {
          ProgressView()
            .opacity(isExporting ? 1 : 0)
          Image(systemName: "square.and.arrow.up")
            .font(.tidexBody)
            .opacity(isExporting ? 0 : 1)
        }
        .accessibilityHidden(true)
      }
      .foregroundStyle(Color.tidexBlueText)
      .padding(.vertical, Spacing.mlg)
      .overlay(alignment: .top) { StatsHairline() }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isExporting)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.dataExportPdfButton))
    .accessibilityValue(Text(period))
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("stats.export")
  }

  /// Side by side, or stacked at accessibility sizes where both don't fit on a line.
  private var labels: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.micro))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
    return layout {
      Text(.dataExportPdfButton)
        .font(.tidexBodyMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(period)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)
        .lineLimit(1)
    }
  }
}

/// The system share sheet for a file made on demand, which `ShareLink` can't present.
struct StatsShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
