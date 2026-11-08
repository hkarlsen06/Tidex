import AppIntents
import SwiftUI

extension ShiftDetailsSheet {

  // MARK: - Sections

  /// Summary card: when, how long and how much, visible at the medium detent.
  var headerSection: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      headerTimeSummary

      if showsEarningsDetails {
        Divider()
        headerPaySummary
      }
    }
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }

  private var headerTimeSummary: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        Text(formattedDate)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)

        Spacer(minLength: 0)

        // Job badge (only shown when user has multiple jobs)
        if let jobName, !jobName.isEmpty {
          WorkplaceNameText(
            name: jobName,
            colorHex: jobColorHex,
            font: .tidexFootnoteMedium,
            fallbackBadgeColor: .tidexBlue,
            lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 1,
            maxTextWidth: dynamicTypeSize.isAccessibilitySize ? nil : 160
          )
        }
      }

      Text(formattedTimeRange)
        .font(.tidexAmountLarge)
        .foregroundStyle(Color.tidexTextPrimary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        .environment(\.layoutDirection, .leftToRight)

      HStack(spacing: Spacing.sm) {
        Text(formattedHours)

        if isVirtualShift {
          Label(.shiftsRecurringShift, systemImage: "repeat")
        }
      }
      .font(.tidexFootnote)
      .foregroundStyle(Color.tidexTextSecondary)
    }
    .accessibilityElement(children: .combine)
  }

  private var headerPaySummary: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(headlinePayLabel)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)

      Spacer()

      Text(formatCurrency(headlinePay))
        .font(.tidexLargeTitle)
        .foregroundStyle(Color.tidexTextPrimary)
    }
    .accessibilityElement(children: .combine)
  }

  var noteSection: some View {
    detailCard {
      detailRow(
        DetailRowItem(
          id: "note",
          systemImage: "note.text",
          title: displayedNote ?? String(localized: .shiftsDetailsNotePlaceholder),
          titleColor: displayedNote == nil ? .tidexTextSecondary : .tidexTextPrimary,
          action: onUpdate == nil ? nil : { beginNoteEditing() }
        )
      )
      .accessibilityHint(onUpdate == nil ? Text(verbatim: "") : Text(.shiftsDetailsNoteEdit))
    }
  }

  // MARK: - Detail Rows

  private struct DetailRowItem: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    var titleColor: Color = .tidexTextPrimary
    var subtitle: String?
    var value: String?
    var action: (() -> Void)?
  }

  /// Secondary settings and navigation, one tappable row each.
  private var detailRowItems: [DetailRowItem] {
    var items: [DetailRowItem] = []

    if shouldShowBreakSection {
      items.append(
        DetailRowItem(
          id: "break",
          systemImage: "pause.circle",
          title: String(localized: .shiftsDetailsBreakRow),
          subtitle: breakRowSubtitle,
          value: deductedPauseMinutes > 0
            ? "\(deductedPauseMinutes) \(String(localized: .commonMinutesShort))" : nil,
          action: canEditPauseWindows ? { openPauseEditor() } : nil
        ))
    }

    if canEditSupplements {
      items.append(
        DetailRowItem(
          id: "supplements",
          systemImage: "slider.horizontal.3",
          title: String(localized: .settingsPayEditorSupplementsTitle),
          action: openSupplementsEditor
        ))
    }

    if snapshotShareContext == .own {
      items.append(
        DetailRowItem(
          id: "pay-settings",
          systemImage: "gearshape",
          title: String(localized: .settingsPayReviewOpen),
          action: { showingPaySettings = true }
        ))
    }

    if canManageRecurring, let recurringId = shift.shift.recurring_id {
      items.append(
        DetailRowItem(
          id: "manage-recurring",
          systemImage: "repeat",
          title: String(localized: .shiftsRecurringManageButton),
          action: {
            // The caller nils out the item binding that presents this sheet and queues
            // the recurring editor to open once the dismiss animation finishes.
            onEditRecurring?(recurringId)
          }
        ))
    }

    if showsCalendarSubscriptionCTA {
      items.append(
        DetailRowItem(
          id: "calendar",
          systemImage: "calendar.badge.clock",
          title: String(localized: .calendarSubscriptionDetailCta),
          action: { showingCalendarSubscriptionConfirmation = true }
        ))
    }

    return items
  }

  func openPauseEditor() {
    impactHaptic.impactOccurred()
    showingPauseEditor = true
  }

  func openSupplementsEditor() {
    impactHaptic.impactOccurred()
    showingSupplementsEditor = true
  }

  private var breakRowSubtitle: String? {
    if !displayedPauseWindows.isEmpty {
      return displayedPauseWindows.map(formatPauseWindow).formatted(
        .list(type: .and, width: .narrow))
    }
    return canEditPauseWindows ? pauseEditorButtonTitle : nil
  }

  var detailRowsSection: some View {
    detailCard {
      ForEach(Array(detailRowItems.enumerated()), id: \.element.id) { index, item in
        if index > 0 {
          Divider()
            .padding(.leading, Spacing.md + Spacing.iconSize + Spacing.sm)
        }
        detailRow(item)
      }
    }
  }

  private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0, content: content)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
  }

  @ViewBuilder
  private func detailRow(_ item: DetailRowItem) -> some View {
    if let action = item.action {
      Button(action: action) {
        detailRowContent(item)
      }
      .buttonStyle(.plain)
    } else {
      detailRowContent(item)
        .accessibilityElement(children: .combine)
    }
  }

  private func detailRowContent(_ item: DetailRowItem) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: item.systemImage)
        .font(.tidexBody)
        .foregroundStyle(Color.tidexTextSecondary)
        .frame(width: Spacing.iconSize)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(item.title)
          .font(.tidexBodyMedium)
          .foregroundStyle(item.titleColor)
          .multilineTextAlignment(.leading)

        if let subtitle = item.subtitle {
          Text(subtitle)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
            .multilineTextAlignment(.leading)
        }
      }

      Spacer(minLength: Spacing.xs)

      if let value = item.value {
        Text(value)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
      }

      if item.action != nil {
        Image(systemName: "chevron.right")
          .font(.tidexCaption)
          .foregroundStyle(Color.tidexTextMuted)
          .flipsForRightToLeftLayoutDirection(true)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }

  // MARK: - Editable Time Section

  var editableTimeSection: some View {
    VStack(spacing: Spacing.md) {
      // Date picker row
      HStack {
        Text(.shiftsDate)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
        Spacer()
        DatePicker(
          String(localized: .shiftsDate),
          selection: $editedDate,
          displayedComponents: .date
        )
        .labelsHidden()
        .tint(.tidexTextPrimary)
      }

      Divider()

      // Time range picker (numeric keyboard input)
      TimeRangePicker(
        startTime: $editedStartTime,
        endTime: $editedEndTime,
        focusedFieldBinding: $focusedTimeField
      )

      // Info about cross-midnight shifts
      if isCrossMidnightShift {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "moon.fill")
            .font(.tidexCaption)
            .foregroundStyle(Color.tidexTextSecondary)
          Text(.shiftsCrossMidnightInfo)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
          Spacer()
        }
        .padding(.top, Spacing.xxs)
      }

      // Virtual shift info (will be converted to regular shift)
      if isVirtualShift {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "info.circle")
            .font(.tidexSubheadline)
            .foregroundStyle(Color.tidexTextSecondary)
          Text(.shiftsVirtualConversionInfo)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
          Spacer()
        }
        .padding(.top, Spacing.xxs)
      }
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }

  var noteEditorSection: some View {
    VStack(spacing: Spacing.md) {
      HStack(alignment: .center, spacing: Spacing.sm) {
        Image(systemName: "note.text")
          .foregroundStyle(Color.tidexTextSecondary)

        Text(.shiftsDetailsNoteTitle)
          .font(.tidexLabelStrong)
          .foregroundStyle(Color.tidexTextSecondary)

        Spacer()
      }

      TextField(
        String(localized: .shiftsDetailsNotePlaceholder),
        text: noteBinding,
        axis: .vertical
      )
      .focused($isNoteFieldFocused)
      .textFieldStyle(.plain)
      .font(.tidexBodyMedium)
      .foregroundStyle(Color.tidexTextPrimary)
      .lineLimit(3...8)
      .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .fill(Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .stroke(Color.tidexBorder, lineWidth: 1)
      )
    }
  }

  /// Whether the edited times represent a cross-midnight shift
  private var isCrossMidnightShift: Bool {
    guard let start = editedStartTime, let end = editedEndTime else {
      return false
    }
    let startStr = formatTimeToString(start)
    let endStr = formatTimeToString(end)
    return endStr <= startStr && endStr != "00:00"
  }

  // MARK: - Error Banner

  @ViewBuilder
  func errorBanner(message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexError)
        .accessibilityHidden(true)
      Text(message)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexError)
      Spacer()
    }
    .announcesToVoiceOver(message)
    .padding(Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexError.opacity(0.1))
    )
  }
}

extension ShiftDetailsSheet {

  /// With no note, an editable shift still shows the row as a way to add one.
  private var shouldShowNoteSection: Bool {
    displayedNote != nil || onUpdate != nil
  }

  private var shouldShowEarningsSection: Bool {
    showsEarningsDetails && (showsPayBreakdownCard || shift.calculationContext != nil)
  }

  private var shouldShowViewModeActionButtons: Bool {
    onUpdate != nil || canStopRecurring
  }

  @ViewBuilder
  var viewModeSections: some View {
    if shouldShowNoteSection {
      noteSection
    }

    if shouldShowEarningsSection {
      earningsSection
    }

    if !detailRowItems.isEmpty {
      detailRowsSection
    }

    if shouldShowViewModeActionButtons {
      viewModeActionButtons
    }

    // Added/edited timestamps (only for non-virtual shifts)
    if !isVirtualShift {
      shiftTimestampFooter(createdAt: shift.createdAt, updatedAt: shift.updatedAt)
    }
  }
}
