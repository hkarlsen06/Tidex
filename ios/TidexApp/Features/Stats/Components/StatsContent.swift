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
      StatsExportRow(action: onExport)
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
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.sm) {
        Text(.dataExportPdfButton)
          .font(.tidexBodyMedium)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "square.and.arrow.up")
          .font(.tidexBody)
          .accessibilityHidden(true)
      }
      .foregroundStyle(Color.tidexBlueText)
      .padding(.vertical, Spacing.mlg)
      .overlay(alignment: .top) { StatsHairline() }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("stats.export")
  }
}
