// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length conditional_returns_on_newline explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface file_types_order identifier_name
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable legacy_objc_type multiline_arguments_brackets no_grouping_extension no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable number_separator prefer_condition_list superfluous_else type_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_contents_order
import SwiftUI

/// A shareable view that mirrors the ShiftDetailsSheet content
/// Renders the shift details exactly as shown in the modal for sharing as a PNG
struct ShareableShiftCard: View {
  let shift: ShiftWithComputations
  let currency: String
  let includeEarnings: Bool
  @Environment(\.layoutDirection) private var layoutDirection

  // MARK: - Computed Properties

  private var formattedDate: String {
    guard let date = Date.fromISODateString(shift.shiftDate) else {
      return shift.shiftDate
    }
    return date.formatted(
      .dateTime.weekday(.wide).day().month(.wide).year().locale(.appLocale)
    ).sentenceCased()
  }

  private var formattedTimeRange: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale,
      separator: " – "
    )
  }

  private var formattedHours: String {
    let hoursLabel = String(localized: .commonHours)
    let formatter = FormatterCache.numberFormatter(includeDecimals: true, locale: Locale.appLocale)
    let hoursValue =
      formatter.string(from: NSNumber(value: shift.paidHours))
      ?? String(format: "%.2f", shift.paidHours)
    return "\(hoursValue) \(hoursLabel)"
  }

  private var showTaxBreakdown: Bool {
    shift.taxEnabled && shift.taxAmount > 0
  }

  private var hasSupplementBreakdown: Bool {
    shift.computed.supplementPay > 0 && !supplementSegments.isEmpty
  }

  private var hasCustomSupplements: Bool {
    if let custom = shift.shift.custom_supplements,
      !custom.rules.isEmpty
    {
      return true
    }
    return false
  }

  private var baseWageRate: Double {
    guard shift.computed.paidHours > 0 else { return 0 }
    return shift.computed.basePay / shift.computed.paidHours
  }

  private var supplementSegments: [SupplementSegment] {
    SupplementSegment.grouped(from: shift.computed.classifiedWagePeriods)
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: Spacing.lg) {
      // Header with date
      headerSection

      // Time section
      timeSection

      // Earnings section (only if included)
      if includeEarnings {
        earningsSection
      }

      // Tidex branding centered
      HStack(spacing: Spacing.xxs) {
        LogoWatermark(opacity: 1.0)
          .frame(width: 14, height: 14)
        Text("Tidex")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.mlg)
    .frame(width: 360)  // Fixed width for consistent sharing
    .background(Color.tidexBackground)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
  }

  // MARK: - Header Section

  private var headerSection: some View {
    VStack(spacing: Spacing.xs) {
      Text(formattedDate)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.xs)
  }

  // MARK: - Time Section

  private var timeSection: some View {
    VStack(spacing: Spacing.md) {
      // Section header
      HStack {
        Image(systemName: "clock")
          .foregroundColor(.tidexBlue)
        Text(.shiftsTimeSection)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      // Time details card
      HStack {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.shiftsTimeRange)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
          Text(formattedTimeRange)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .environment(\.layoutDirection, .leftToRight)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: Spacing.xxs) {
          Text(.shiftsDuration)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
          Text(formattedHours)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
        }
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  // MARK: - Earnings Section

  private var earningsSection: some View {
    VStack(spacing: Spacing.md) {
      // Section header
      HStack {
        Image(systemName: "creditcard")
          .foregroundColor(.tidexBlue)
        Text(.shiftsEarningsSection)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)
        Spacer()
      }

      // Earnings card
      VStack(spacing: Spacing.sm) {
        // Base Pay (only show when there are supplements)
        if hasSupplementBreakdown {
          earningsRow(
            label: String(localized: .shiftsBasePay),
            value: formatCurrency(shift.computed.basePay)
          )

          Divider()
        }

        // Supplement breakdown section
        if hasSupplementBreakdown {
          supplementBreakdownSection
        }

        // Gross
        earningsRow(
          label: String(localized: .shiftsGrossPay),
          value: formatCurrency(shift.grossPay),
          isHighlighted: !showTaxBreakdown && !hasSupplementBreakdown
        )

        if showTaxBreakdown {
          Divider()

          // Tax deduction
          earningsRow(
            label: String(localized: .shiftsTaxDeduction),
            value: "−\(formatCurrency(shift.taxAmount))",
            valueColor: .tidexError
          )

          Divider()

          // Net (highlighted)
          earningsRow(
            label: String(localized: .shiftsNetPay),
            value: formatCurrency(shift.netPay),
            isHighlighted: true
          )
        }
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
    }
  }

  // MARK: - Supplement Breakdown

  @ViewBuilder
  private var supplementBreakdownSection: some View {
    VStack(spacing: Spacing.sm) {
      // Total supplement header with optional "Customized" badge
      HStack {
        HStack(spacing: Spacing.xs) {
          Text(
            shift.computed.overtimeApplied ? .shiftsSupplementsAndOvertime : .shiftsTotalSupplement
          )
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)

          if hasCustomSupplements {
            Text(.shiftsCustomized)
              .font(.tidexMicro)
              .foregroundColor(.tidexBlue)
              .padding(.horizontal, Spacing.xs)
              .padding(.vertical, 3)
              .background(
                Capsule()
                  .fill(Color.tidexBlue.opacity(0.15))
              )
          }
        }

        Spacer()

        Text(formatCurrency(shift.computed.supplementPay))
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)
      }

      // Individual supplement segments
      ForEach(supplementSegments) { segment in
        supplementSegmentRow(segment)
      }

      Divider()
    }
  }

  @ViewBuilder
  private func supplementSegmentRow(_ segment: SupplementSegment) -> some View {
    VStack(spacing: Spacing.xxxs) {
      // Time range and hours × rate
      HStack {
        Text(segmentTimeRange(segment))
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
          .environment(\.layoutDirection, .leftToRight)

        Spacer()

        Text("\(formatHoursValue(segment.actualHours)) × \(formatCurrency(segment.rate))")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
      }

      // Supplement label and amount
      HStack {
        Text(segment.isOvertime ? .shiftsOvertimeLabel : .shiftsSupplementLabel)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Text(formatCurrency(segment.amount))
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)
      }
    }
    .padding(Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexSurfaceSecondary.opacity(0.4))
    )
  }

  // MARK: - Helper Views

  @ViewBuilder
  private func earningsRow(
    label: String,
    value: String,
    isHighlighted: Bool = false,
    valueColor: Color = .tidexTextPrimary
  ) -> some View {
    HStack {
      Text(label)
        .font(isHighlighted ? .tidexLabel : .tidexSubheadline)
        .foregroundColor(isHighlighted ? .tidexTextPrimary : .tidexTextSecondary)

      Spacer()

      Text(value)
        .font(.system(size: isHighlighted ? 20 : 15, weight: isHighlighted ? .semibold : .medium))
        .foregroundColor(valueColor)
    }
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  private func formatHoursValue(_ hours: Double) -> String {
    ShiftCardFormatter.formattedHours(hours, locale: .appLocale)
  }

  private func segmentTimeRange(_ segment: SupplementSegment) -> String {
    let range = segment.timeRange
    guard layoutDirection == .rightToLeft else { return range }
    let parts = range.components(separatedBy: " – ")
    if parts.count == 2 {
      return "\(parts[1]) – \(parts[0])"
    }
    return range
  }
}

// MARK: - Image Rendering Extension

extension ShareableShiftCard {
  /// Renders the view as a PNG image
  @MainActor
  func renderAsImage() -> UIImage? {
    let renderer = ImageRenderer(content: self)
    renderer.scale = 3.0  // High resolution for sharing
    return renderer.uiImage
  }
}
