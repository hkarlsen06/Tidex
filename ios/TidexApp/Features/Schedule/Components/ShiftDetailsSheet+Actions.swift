import AppIntents
import SwiftUI

extension ShiftDetailsSheet {

  // MARK: - Action Buttons

  var editOptionsSection: some View {
    VStack(spacing: Spacing.sm) {
      if canEditSupplements {
        inlineEditOptionButton(
          title: String(localized: .supplementsEditButton),
          systemImage: "slider.horizontal.3"
        ) {
          openSupplementsEditor()
        }
      }

      if canEditPauseWindows {
        inlineEditOptionButton(
          title: pauseEditorButtonTitle,
          systemImage: hasCustomPauseWindows ? "pencil.circle" : "plus.circle"
        ) {
          openPauseEditor()
        }
      }
    }
  }

  private func inlineEditOptionButton(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: systemImage)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextPrimary)
        Text(title)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexBlueText)
      }
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity)
      .background(Color.tidexBlue.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  /// Action buttons for view mode
  var viewModeActionButtons: some View {
    VStack(spacing: Spacing.sm) {
      // Edit button (only show if onUpdate callback is provided)
      if onUpdate != nil {
        DetailSheetActionButton(
          title: String(localized: .shiftsEditButton),
          systemImage: "pencil",
          style: .primary
        ) {
          withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            isEditing = true
          }
        }
      }

      if canStopRecurring {
        DetailSheetActionButton(
          title: String(localized: .shiftsRecurringStopAfterDateButton),
          systemImage: "calendar.badge.minus",
          style: .secondary
        ) {
          showingStopRecurringConfirmation = true
        }
        .disabled(isStoppingRecurringAfterDate)
      }
    }
  }

  /// The parts that add up to the headline pay. The total itself lives in the header.
  var earningsSection: some View {
    VStack(spacing: Spacing.sm) {
      if showsPayBreakdownCard {
        EarningsBreakdownCard {
          payComponentRows
          taxRows
        }
      }

      if let context = shift.calculationContext {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(
            .settingsPayReviewTaxDate(
              Date.fromISODateString(context.scheduledPayoutDate)?
                .formatted(.dateTime.day().month(.wide).year().calendar(.gregorian))
                ?? context.scheduledPayoutDate)
          )
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          if context.halfTaxApplied {
            Text(.settingsPayReviewHalfTax)
              .font(.tidexFootnote)
              .foregroundStyle(Color.tidexTextSecondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func breakDeductionSection(_ breakdown: BreakDeductionBreakdown) -> some View {
    VStack(spacing: Spacing.xs) {
      let canExpand = breakdown.parts.count > 1

      if canExpand {
        Button {
          impactHaptic.impactOccurred()
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            isBreakDeductionExpanded.toggle()
          }
        } label: {
          breakDeductionTotalRow(breakdown, showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(breakDeductionLabel)
        .accessibilityValue(
          expansionValue(
            "−\(formatCurrency(breakdown.totalAmount))", isExpanded: isBreakDeductionExpanded)
        )
        .accessibilityHint(Text(.shiftsBreakDeductionExpandAccessibilityHint))
      } else {
        breakDeductionTotalRow(breakdown, showsChevron: false)
      }

      if canExpand, isBreakDeductionExpanded {
        VStack(spacing: Spacing.xs) {
          ForEach(breakdown.parts) { part in
            breakDeductionPartView(part)
          }

          Text(breakDeductionExplanation)
            .font(.tidexCaptionRegular)
            .foregroundStyle(Color.tidexTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.xxxs)
        }
        .padding(.top, Spacing.xxxs)
      }
    }
  }

  @ViewBuilder
  private var payComponentRows: some View {
    if hasEarningsBreakdown {
      earningsRow(
        label: String(localized: .shiftsBasePay),
        value: formatCurrency(displayedBasePay)
      )

      if hasSupplementBreakdown {
        Divider()
        supplementBreakdownSection
      }

      if hasOvertimeBreakdown {
        Divider()
        overtimeBreakdownSection
      }

      if shouldShowBreakDeductionRow, let breakdown = breakDeductionBreakdown {
        Divider()
        breakDeductionSection(breakdown)
      }
    }
  }

  @ViewBuilder
  private var taxRows: some View {
    if showTaxBreakdown {
      if hasEarningsBreakdown {
        Divider()
      }

      earningsRow(
        label: String(localized: .shiftsGrossPay),
        value: formatCurrency(shift.grossPay)
      )

      Divider()

      earningsRow(
        label: String(localized: .shiftsTaxDeduction),
        value: "−\(formatCurrency(shift.taxAmount))",
        valueColor: .tidexError
      )
    }
  }

  private func breakDeductionTotalRow(
    _ breakdown: BreakDeductionBreakdown,
    showsChevron: Bool
  ) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(breakDeductionLabel)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)

      if showsChevron {
        Image(systemName: "chevron.down")
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextMuted)
          .rotationEffect(.degrees(isBreakDeductionExpanded ? 180 : 0))
      }

      Spacer()

      Text("−\(formatCurrency(breakdown.totalAmount))")
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexError)
    }
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func breakDeductionPartView(_ part: BreakDeductionPart) -> some View {
    switch part.kind {
    case .base:
      breakDeductionBasePayCard(part)

    case .supplement:
      breakDeductionSupplementCard(part)
    }
  }

  private func breakDeductionBasePayCard(_ part: BreakDeductionPart) -> some View {
    EarningsBreakDeductionDetailCard(
      title: String(localized: .shiftsBreakDeductionPartBasePay),
      amount: "−\(formatCurrency(part.amount))",
      detailTitle: String(localized: .shiftsBreakDeduction),
      detailValue: part.rate.map { "\(formatHoursValue(part.hours)) × \(formatCurrency($0))" }
        ?? formatHoursValue(part.hours)
    )
  }

  @ViewBuilder
  private func breakDeductionSupplementCard(_ part: BreakDeductionPart) -> some View {
    if let segment = part.supplementSegment {
      EarningsBreakDeductionDetailCard(
        title: String(localized: .shiftsBreakDeductionPartSupplement),
        amount: "−\(formatCurrency(part.amount))",
        detailTitle: segmentTimeRange(segment),
        detailValue: "\(formatHoursValue(part.hours)) × \(formatCurrency(segment.rate))",
        forcesLeftToRight: true
      )
    } else {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
        Text(.shiftsBreakDeductionPartSupplement)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextMuted)

        Spacer()

        Text("\(formatHoursValue(part.hours)) / −\(formatCurrency(part.amount))")
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
    }
  }

  /// Supplement breakdown showing each time period with supplements
  @ViewBuilder
  private var supplementBreakdownSection: some View {
    VStack(spacing: Spacing.sm) {
      let canExpand = !supplementSegments.isEmpty

      if canExpand {
        Button {
          impactHaptic.impactOccurred()
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            isSupplementBreakdownExpanded.toggle()
          }
        } label: {
          supplementTotalRow(showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.shiftsTotalSupplement))
        .accessibilityValue(
          expansionValue(
            formatCurrency(displayedSupplementPay), isExpanded: isSupplementBreakdownExpanded)
        )
        .accessibilityHint(Text(.shiftsAccessibilityExpandHint))
      } else {
        supplementTotalRow(showsChevron: false)
      }

      if canExpand, isSupplementBreakdownExpanded {
        ForEach(supplementSegments) { segment in
          supplementSegmentRow(segment)
        }
      }
    }
  }

  private func supplementTotalRow(showsChevron: Bool) -> some View {
    HStack(spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        Text(.shiftsTotalSupplement)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)

        if showsChevron {
          Image(systemName: "chevron.down")
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextMuted)
            .rotationEffect(.degrees(isSupplementBreakdownExpanded ? 180 : 0))
            .accessibilityHidden(true)
        }

        if hasCustomSupplements {
          Text(.shiftsCustomized)
            .font(.tidexMicro)
            .foregroundStyle(Color.tidexBlueText)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
              Capsule()
                .fill(Color.tidexBlue.opacity(0.15))
            )
        }
      }

      Spacer()

      Text(formatCurrency(displayedSupplementPay))
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextPrimary)
    }
    .contentShape(Rectangle())
  }

  /// Overtime breakdown showing periods where weekly overtime applied.
  @ViewBuilder
  private var overtimeBreakdownSection: some View {
    VStack(spacing: Spacing.sm) {
      let canExpand = !overtimeSegments.isEmpty

      if canExpand {
        Button {
          impactHaptic.impactOccurred()
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            isOvertimeBreakdownExpanded.toggle()
          }
        } label: {
          overtimeTotalRow(showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.shiftsOvertimeLabel))
        .accessibilityValue(
          expansionValue(
            formatCurrency(displayedOvertimePay), isExpanded: isOvertimeBreakdownExpanded)
        )
        .accessibilityHint(Text(.shiftsAccessibilityExpandHint))
      } else {
        overtimeTotalRow(showsChevron: false)
      }

      if canExpand, isOvertimeBreakdownExpanded {
        ForEach(overtimeSegments) { segment in
          overtimeSegmentRow(segment)
        }
      }
    }
  }

  private func overtimeTotalRow(showsChevron: Bool) -> some View {
    HStack(spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        Text(.shiftsOvertimeLabel)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)

        if showsChevron {
          Image(systemName: "chevron.down")
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextMuted)
            .rotationEffect(.degrees(isOvertimeBreakdownExpanded ? 180 : 0))
            .accessibilityHidden(true)
        }
      }

      Spacer()

      Text(formatCurrency(displayedOvertimePay))
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextPrimary)
    }
    .contentShape(Rectangle())
  }

  /// A single supplement segment row showing time range, hours × rate, and amount
  @ViewBuilder
  private func supplementSegmentRow(_ segment: SupplementSegment) -> some View {
    EarningsSupplementBreakdownDetailCard(
      timeRange: segmentTimeRange(segment),
      hoursAndRate: "\(formatHoursValue(segment.actualHours)) × \(formatCurrency(segment.rate))",
      amount: formatCurrency(segment.amount)
    )
  }

  @ViewBuilder
  private func overtimeSegmentRow(_ segment: SupplementSegment) -> some View {
    EarningsSupplementBreakdownDetailCard(
      title: String(localized: .shiftsOvertimeLabel),
      timeRange: segmentTimeRange(segment),
      hoursAndRate: "\(formatHoursValue(segment.actualHours)) × \(formatCurrency(segment.rate))",
      amount: formatCurrency(segment.amount)
    )
  }

  /// Spoken amount followed by whether the row's details are showing.
  private func expansionValue(_ amount: String, isExpanded: Bool) -> Text {
    let state =
      isExpanded
      ? String(localized: .shiftsAccessibilityExpanded)
      : String(localized: .shiftsAccessibilityCollapsed)
    return Text(verbatim: "\(amount), \(state)")
  }

  /// Format hours value (e.g., "2.50 t")
  private func formatHoursValue(_ hours: Double) -> String {
    ShiftCardFormatter.formattedHours(hours, locale: .appLocale)
  }

  func formatPauseWindow(_ window: PauseWindow) -> String {
    "\(window.start) – \(window.end)"
  }

  func durationMinutes(for window: PauseWindow) -> Int {
    let start = minutes(for: window.start)
    var end = minutes(for: window.end)
    if end <= start {
      end += 24 * 60
    }
    return end - start
  }

  func minutes(for hhmm: String) -> Int {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else {
      return 0
    }
    return (parts[0] * 60) + parts[1]
  }

  private func segmentTimeRange(_ segment: SupplementSegment) -> String {
    let range = segment.timeRange
    guard layoutDirection == .rightToLeft else {
      return range
    }
    let parts = range.components(separatedBy: " – ")
    if parts.count == 2 {
      return "\(parts[1]) – \(parts[0])"
    }
    return range
  }

  @ViewBuilder
  private func earningsRow(
    label: String,
    value: String,
    valueColor: Color = .tidexTextPrimary
  ) -> some View {
    EarningsBreakdownCard<EmptyView>.Row(
      label: label,
      value: value,
      valueColor: valueColor
    )
  }

  /// Footer showing when the shift was added and, when applicable, last edited.
  @ViewBuilder
  func shiftTimestampFooter(createdAt: Date?, updatedAt: Date?) -> some View {
    if let createdAt {
      VStack(spacing: Spacing.xxs) {
        Text(String(localized: .shiftsAdded) + " " + formattedShiftTimestamp(createdAt))

        if let updatedAt, !timestampsMatch(createdAt, updatedAt) {
          Text(String(localized: .shiftsLastEdited) + " " + formattedShiftTimestamp(updatedAt))
        }
      }
      .font(.tidexCaptionRegular)
      .foregroundStyle(Color.tidexTextMuted)
      .frame(maxWidth: .infinity)
      .padding(.top, Spacing.xs)
    } else if let updatedAt {
      Text(String(localized: .shiftsLastEdited) + " " + formattedShiftTimestamp(updatedAt))
        .font(.tidexCaptionRegular)
        .foregroundStyle(Color.tidexTextMuted)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xs)
    }
  }

  private func timestampsMatch(_ lhs: Date, _ rhs: Date) -> Bool {
    abs(lhs.timeIntervalSince(rhs)) < 1
  }

  /// Format shift metadata dates with relative or absolute formatting.
  private func formattedShiftTimestamp(_ date: Date) -> String {
    let calendar = Calendar.gregorianCurrent
    let now = Date()

    // If within the last 7 days, use relative formatting
    if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .full
      return formatter.localizedString(for: date, relativeTo: now)
    }
    // Otherwise use a short date format
    let formatter = DateFormatter()  // swiftlint:disable:this explicit_type_interface
    formatter.locale = Locale.appLocale
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  // MARK: - Formatting

  func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  var viewerUserId: String? {
    coordinator.getCurrentUserId()
  }

  var canSendShiftSnapshots: Bool {
    FriendsMessagingCapabilities.shared.canSendShiftSnapshots
  }

  func makeShiftSnapshotDraft(for recipient: ShareRecipient) throws
    -> ComposerShiftSnapshotDraft
  {
    switch snapshotShareContext {
    case .own:
      guard let viewerUserId else {
        throw FriendsMessagingServiceError.notAuthenticated
      }
      return OwnShiftSnapshotBuilder(
        shift: shift,
        jobName: jobName,
        jobColorHex: jobColorHex,
        currency: currency,
        ownerUserId: viewerUserId,
        ownerDisplayName: coordinator.userDisplayName,
        ownerAvatarUrl: coordinator.userAvatarUrl
      )
      .build(for: recipient)

    case .shared(let owner):
      return SharedShiftSnapshotBuilder(
        shift: shift,
        jobName: jobName,
        jobColorHex: jobColorHex,
        currency: currency,
        owner: owner
      )
      .build()
    }
  }
}
