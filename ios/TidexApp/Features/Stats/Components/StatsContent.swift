import SwiftUI

/// The Stats drawing for one month. It holds no view model, so the design-review screens render
/// it from fixtures. A new lattice swaps values in place in one animation, and nothing changes
/// position or size.
struct StatsContent: View {
  let lattice: StatsLattice
  let onSelectMonth: (Int) -> Void
  let onExport: () -> Void
  var onScrubbingChange: (Bool) -> Void = { _ in }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StatsHero(hero: lattice.hero, metrics: lattice.metrics)
      StatsPaceSection(pace: lattice.pace, onScrubbingChange: onScrubbingChange)
        .padding(.top, StatsRhythm.section)
      StatsWeeksSection(weeks: lattice.weeks)
        .padding(.top, StatsRhythm.section)
      StatsYearSection(year: lattice.year, onSelectMonth: onSelectMonth)
        .padding(.top, StatsRhythm.section)
      StatsExportRow(action: onExport)
        .padding(.top, StatsRhythm.section)
    }
    .animation(
      MotionTokens.optionalAnimation(.emphasis, reduceMotion: reduceMotion), value: lattice)
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
      .padding(.bottom, MonthPickerLayout.totalBottomInset + Spacing.md)
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
