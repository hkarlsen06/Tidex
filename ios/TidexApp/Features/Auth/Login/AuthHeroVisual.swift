import SwiftUI

// MARK: - Shared Auth Hero Visual

struct AuthHeroVisual: View {
  let title: LocalizedStringResource
  let logoSize: CGFloat
  let currency: String
  var subtitle: LocalizedStringResource?
  /// The shift saved in the pre-auth demo. It replaces the sample paycheck card.
  var demoShift: PreAuthDemoShift?

  var body: some View {
    VStack(spacing: Spacing.lg) {
      logoRow
      if let demoShift {
        AuthDemoShiftCard(shift: demoShift)
      } else {
        ghostedPaycheckPreview
      }
      Text(title)
        .font(.tidexTitle)
        .foregroundStyle(Color.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      if let subtitle {
        Text(subtitle)
          .font(.tidexBody)
          .foregroundStyle(Color.tidexTextSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, -Spacing.sm)
      }
    }
  }

  private var logoRow: some View {
    Image("TidexLogo")
      .resizable()
      .scaledToFit()
      .frame(width: min(logoSize, Spacing.huge), height: min(logoSize, Spacing.huge))
      .accessibilityHidden(true)
      .frame(maxWidth: .infinity)
  }

  private var ghostedAmountText: String {
    let hourlyWage = OnboardingCurrencyResolver.defaultHourlyWage(for: currency)
    let estimatedMonthlyHours = 162.0
    let estimatedNet = hourlyWage * estimatedMonthlyHours * 0.8
    return CurrencyConfig.format(estimatedNet, currency: currency)
  }

  @ViewBuilder
  private var ghostedPaycheckPreview: some View {
    let card = ZStack {
      VStack(spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.2))
          .frame(width: 80, height: 8)

        Spacer().frame(height: 4)

        Text(ghostedAmountText)
          .font(.tidexAmountLarge)
          .foregroundStyle(Color.tidexTextPrimary)

        Spacer().frame(height: 8)

        ghostedRow(labelWidth: 80, valueWidth: 55)
        ghostedRow(labelWidth: 65, valueWidth: 50)
        ghostedRow(labelWidth: 90, valueWidth: 60)
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.mlg)
      .frame(maxWidth: .infinity)
      .background(heroCardBackground)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
          .stroke(Color.tidexSeparator, lineWidth: 1)
      )

    }

    card.accessibilityHidden(true)
  }

  private func ghostedRow(labelWidth: CGFloat, valueWidth: CGFloat) -> some View {
    HStack {
      RoundedRectangle(cornerRadius: 3)
        .fill(Color.tidexTextMuted.opacity(0.2))
        .frame(width: labelWidth, height: 6)
      Spacer()
      RoundedRectangle(cornerRadius: 3)
        .fill(Color.tidexTextMuted.opacity(0.2))
        .frame(width: valueWidth, height: 6)
    }
  }

  private var heroCardBackground: some View {
    Color.tidexSurfacePrimary
  }

}

/// The demo shift on the sign-up screen: one tile per date under its month, then the times.
private struct AuthDemoShiftCard: View {
  let shift: PreAuthDemoShift

  private var days: [Date] { shift.dates.compactMap { Date.fromISODateString($0) } }

  private var monthsText: String {
    var months: [String] = []
    for day in days {
      let month = day.formatted(.dateTime.month(.wide).locale(.appLocale))
      if months.last != month { months.append(month) }
    }
    return months.formatted(.list(type: .and).locale(.appLocale))
  }

  private var timeText: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime, end: shift.endTime, locale: .appLocale)
  }

  private var spokenDates: String {
    days.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.appLocale)) }
      .formatted(.list(type: .and).locale(.appLocale))
  }

  var body: some View {
    VStack(spacing: Spacing.sm) {
      Text(verbatim: monthsText)
        .font(.tidexCaptionStrong)
        .foregroundStyle(Color.tidexTextSecondary)
      CenteredFlowLayout(spacing: Spacing.xxs + 2) {
        ForEach(days, id: \.self) { day in
          dateTile(day)
        }
      }
      Text(verbatim: timeText)
        .font(.tidexAmountLarge)
        .monospacedDigit()
        .foregroundStyle(Color.tidexBlueText)
        .padding(.top, Spacing.xxs)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.mlg)
    .frame(maxWidth: .infinity)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .stroke(Color.tidexSeparator, lineWidth: 1)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "\(spokenDates), \(timeText)"))
  }

  private func dateTile(_ day: Date) -> some View {
    VStack(spacing: 2) {
      Text(verbatim: day.formatted(.dateTime.weekday(.abbreviated).locale(.appLocale)))
        .font(.tidexCaption)
        .foregroundStyle(Color.tidexTextSecondary)
      Text(verbatim: day.formatted(.dateTime.day().locale(.appLocale)))
        .font(.tidexHeadline)
        .monospacedDigit()
        .foregroundStyle(Color.tidexTextPrimary)
    }
    .frame(minWidth: 40)
    .padding(.vertical, Spacing.xs)
    .background(
      Color.tidexSurfaceSecondary,
      in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

/// Lays its children out in centred rows that wrap at the available width. Rows share the
/// children evenly, so eight tiles become four and four rather than seven and one.
private struct CenteredFlowLayout: Layout {
  let spacing: CGFloat

  private struct Row {
    let indices: [Int]
    let width: CGFloat
    let height: CGFloat
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = rows(fitting: proposal.width ?? .infinity, subviews: subviews)
    let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in rows(fitting: bounds.width, subviews: subviews) {
      var x = bounds.midX - row.width / 2
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private func rows(fitting maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    var fitsOnFirstRow = 0
    var width: CGFloat = 0
    for size in sizes {
      width += (fitsOnFirstRow == 0 ? 0 : spacing) + size.width
      if width > maxWidth, fitsOnFirstRow > 0 { break }
      fitsOnFirstRow += 1
    }
    guard fitsOnFirstRow > 0 else { return [] }
    let rowCount = (sizes.count + fitsOnFirstRow - 1) / fitsOnFirstRow
    let perRow = (sizes.count + rowCount - 1) / rowCount
    return stride(from: 0, to: sizes.count, by: perRow).map { start in
      let indices = Array(start..<min(start + perRow, sizes.count))
      return Row(
        indices: indices,
        width: indices.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(indices.count - 1),
        height: indices.map { sizes[$0].height }.max() ?? 0)
    }
  }
}

/// The chevron pill that leaves a pre-auth or auth screen for the previous page.
struct PreAuthBackButton: View {
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.play(.light)
      action()
    } label: {
      Image(systemName: "chevron.left")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.tidexTextSecondary)
        .accessibilityHidden(true)
        .frame(width: 46, height: 34)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(SnappyButtonStyle())
    .accessibilityLabel(Text(.commonBack))
    .accessibilityIdentifier("auth.back")
  }
}
