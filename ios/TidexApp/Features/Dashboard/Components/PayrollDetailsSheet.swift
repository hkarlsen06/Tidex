import SwiftUI

struct PayrollAdjustmentDraft {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let jobId: String?  // swiftlint:disable:this explicit_acl
  let amount: Double  // swiftlint:disable:this explicit_acl
  let currency: String  // swiftlint:disable:this explicit_acl
  let category: PayrollAdjustmentCategory  // swiftlint:disable:this explicit_acl
  let taxTreatment: PayrollAdjustmentTaxTreatment  // swiftlint:disable:this explicit_acl
  let description: String  // swiftlint:disable:this explicit_acl
  let note: String?  // swiftlint:disable:this explicit_acl
  let earnedFromDate: Date?  // swiftlint:disable:this explicit_acl
  let earnedToDate: Date?  // swiftlint:disable:this explicit_acl
  let payoutDate: Date  // swiftlint:disable:this explicit_acl
}

struct PayrollDetailsSheet: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  let variant: PayrollCardVariant  // swiftlint:disable:this explicit_acl
  var onCreateAdjustment: ((PayrollAdjustmentDraft) async throws -> PayrollAdjustment)?  // swiftlint:disable:this explicit_acl line_length
  var onUpdateAdjustment: ((String, PayrollAdjustmentDraft) async throws -> PayrollAdjustment)?  // swiftlint:disable:this explicit_acl line_length
  var onDeleteAdjustment: ((String) async throws -> Void)?  // swiftlint:disable:this explicit_acl

  @Environment(\.dismiss) private var dismiss  // swiftlint:disable:this explicit_type_interface
  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface
  @State private var expandedSupplementJobIds: Set<String> = []
  @State private var expandedPostDeductionJobIds: Set<String> = []
  @State private var expandedAdjustmentSectionIds: Set<String> = []
  @State private var createdAdjustmentsByJobId: [String: [PayrollAdjustment]] = [:]
  @State private var editedAdjustmentsById: [String: PayrollAdjustment] = [:]
  @State private var deletedAdjustmentIds: Set<String> = []
  @State private var adjustmentFormContext: PayrollAdjustmentFormContext?
  @State private var curatedAdjustmentContext: PayrollAdjustmentCuratedContext?

  private var totalNet: Double {
    displayedBreakdowns.reduce(0) { $0 + displayAmount(for: $1) }
  }

  private var totalGross: Double {
    displayedBreakdowns.reduce(0) { $0 + $1.gross }
  }

  private var totalTax: Double {
    displayedBreakdowns.reduce(0) { $0 + ($1.tax ?? 0) }
  }

  private var showTaxBreakdown: Bool {
    totalTax > 0
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.lg) {
          earningsSection
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xxl)
      }
      .background(Color.tidexBackground.ignoresSafeArea())
      .navigationTitle(String(localized: .dashboardPayrollDetailsTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: .commonDone)) {
            dismiss()
          }
        }
      }
    }
    .sheet(item: $adjustmentFormContext) { context in
      PayrollAdjustmentFormSheet(
        context: context,
        onSave: { draft in
          if let adjustment = context.adjustment {
            guard let onUpdateAdjustment else { return }  // swiftlint:disable:this conditional_returns_on_newline
            let updated = try await onUpdateAdjustment(adjustment.id, draft)  // swiftlint:disable:this explicit_type_interface
            replaceAdjustment(updated, in: context.breakdown.id)
          } else {
            guard let onCreateAdjustment else { return }  // swiftlint:disable:this conditional_returns_on_newline
            let adjustment = try await onCreateAdjustment(draft)  // swiftlint:disable:this explicit_type_interface
            createdAdjustmentsByJobId[context.breakdown.id, default: []].append(adjustment)
          }
        },
        onDelete: context.adjustment == nil
          ? nil
          : {
            guard let adjustment = context.adjustment, let onDeleteAdjustment else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
            try await onDeleteAdjustment(adjustment.id)
            removeAdjustment(adjustment.id, from: context.breakdown.id)
          }
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $curatedAdjustmentContext) { context in
      PayrollAdjustmentCuratedSheet(context: context)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
  }

  private var earningsSection: some View {
    VStack(spacing: Spacing.sm) {
      ForEach(Array(displayedBreakdowns.enumerated()), id: \.element.id) { index, breakdown in
        jobBreakdownSection(breakdown)

        if index < displayedBreakdowns.count - 1 {
          workplaceDivider
        }
      }

      if displayedBreakdowns.count > 1 {
        workplaceDivider

        earningsRow(
          label: String(
            localized: showTaxBreakdown
              ? .dashboardPayrollDetailsTotalGross : .dashboardPayrollDetailsTotalNet),  // swiftlint:disable:this line_length multiline_arguments_brackets
          value: formatCurrency(
            showTaxBreakdown ? totalGross : totalNet, currency: variant.currency),  // swiftlint:disable:this line_length multiline_arguments_brackets
          isHighlighted: !showTaxBreakdown
        )

        if showTaxBreakdown {
          earningsRow(
            label: String(localized: .dashboardPayrollDetailsTotalTax),
            value: "−\(formatCurrency(totalTax, currency: variant.currency))",
            valueColor: .tidexError
          )
        }

        earningsRow(
          label: String(localized: .dashboardPayrollDetailsTotalNet),
          value: formatCurrency(totalNet, currency: variant.currency),
          isHighlighted: true
        )
      }
    }
  }

  private var displayedBreakdowns: [PayrollCardJobBreakdown] {
    if variant.jobBreakdowns.isEmpty {
      return [
        PayrollCardJobBreakdown(
          id: variant.id,
          title: variant.title,
          colorHex: variant.colorHex,
          currency: variant.currency,
          basePay: variant.gross,
          supplementPay: 0,
          supplementBreakdowns: [],
          postDeductions: 0,
          postDeductionParts: [],
          payoutDate: variant.payoutDate,
          gross: variant.gross,
          net: variant.net,
          tax: variant.tax,
          taxEnabled: variant.taxEnabled,
          adjustments: []
        )
      ]
    }

    return variant.jobBreakdowns.map { breakdown in
      let persisted = breakdown.adjustments.compactMap { adjustment -> PayrollAdjustment? in  // swiftlint:disable:this explicit_type_interface line_length
        guard !deletedAdjustmentIds.contains(adjustment.id) else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
        return editedAdjustmentsById[adjustment.id] ?? adjustment
      }
      let additions = (createdAdjustmentsByJobId[breakdown.id] ?? [])  // swiftlint:disable:this explicit_type_interface
        .filter { !deletedAdjustmentIds.contains($0.id) && editedAdjustmentsById[$0.id] == nil }
      return breakdown.withAdjustments(persisted + additions)
    }
  }

  private var workplaceDivider: some View {
    RoundedRectangle(cornerRadius: 1)
      .fill(Color.tidexBorder.opacity(0.85))  // swiftlint:disable:this no_magic_numbers
      .frame(height: 2)  // swiftlint:disable:this no_magic_numbers
      .padding(.vertical, Spacing.xs)
  }

  @ViewBuilder
  private func jobBreakdownSection(_ breakdown: PayrollCardJobBreakdown) -> some View {  // swiftlint:disable:this function_body_length line_length
    VStack(spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
      HStack(spacing: Spacing.xs) {
        WorkplaceNameText(
          name: breakdown.title,
          colorHex: breakdown.colorHex,
          font: .tidexBodyMedium,
          fallbackBadgeColor: .tidexBlue,
          badgeHorizontalPadding: Spacing.xs,
          badgeVerticalPadding: 1
        )

        Spacer()

        Text(ShiftCardFormatter.dateParts(for: breakdown.payoutDate).dayMonth)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextMuted)
          .lineLimit(1)
      }

      EarningsBreakdownCard<EmptyView>.Row(
        label: String(localized: .shiftsBasePay),
        value: formatCurrency(breakdown.basePay, currency: breakdown.currency)
      )

      if breakdown.supplementPay > 0 {
        Divider()
        supplementBreakdownSection(breakdown)
      }

      if breakdown.postDeductions > 0 {
        Divider()
        postDeductionBreakdownSection(breakdown)
      }

      if breakdown.taxEnabled,
        !taxableAdjustments(for: breakdown).isEmpty || onCreateAdjustment != nil
      {
        Divider()
        taxableAdjustmentBreakdownSection(breakdown)
      }

      if showsTaxDeduction(for: breakdown), let tax = breakdown.tax {
        Divider()

        EarningsBreakdownCard<EmptyView>.Row(
          label: String(localized: .dashboardPayrollDetailsGross),
          value: formatCurrency(preDirectPayoutAmount(for: breakdown), currency: breakdown.currency)
        )

        Divider()

        EarningsBreakdownCard<EmptyView>.Row(
          label: String(localized: .dashboardPayrollDetailsEstimatedTax),
          value: "−\(formatCurrency(tax, currency: breakdown.currency))",
          valueColor: .tidexError
        )
      }

      if breakdown.taxEnabled, !directPayoutAdjustments(for: breakdown).isEmpty {
        Divider()
        directPayoutAdjustmentBreakdownSection(breakdown)
      }

      if !breakdown.taxEnabled,
        !directPayoutAdjustments(for: breakdown).isEmpty || onCreateAdjustment != nil
      {
        Divider()
        directPayoutAdjustmentBreakdownSection(breakdown)
      }

      Divider()

      EarningsBreakdownCard<EmptyView>.Row(
        label: String(localized: .dashboardPayrollDetailsNet),
        value: formatCurrency(displayAmount(for: breakdown), currency: breakdown.currency),
        isHighlighted: true
      )
    }
  }

  private func adjustmentBreakdownSection(  // swiftlint:disable:this function_body_length
    _ breakdown: PayrollCardJobBreakdown,
    kind: AdjustmentSectionKind,
    adjustments: [PayrollAdjustment],
    showsAddButton: Bool
  ) -> some View {
    VStack(spacing: Spacing.xs) {  // swiftlint:disable:this closure_body_length
      let sectionId = adjustmentSectionId(breakdown, kind: kind)  // swiftlint:disable:this explicit_type_interface
      let isExpanded = expandedAdjustmentSectionIds.contains(sectionId)  // swiftlint:disable:this explicit_type_interface line_length

      Button {
        withAnimation(.easeInOut(duration: 0.18)) {  // swiftlint:disable:this no_magic_numbers
          if isExpanded {
            expandedAdjustmentSectionIds.remove(sectionId)
          } else {
            expandedAdjustmentSectionIds.insert(sectionId)
          }
        }
      } label: {
        adjustmentTotalRow(
          breakdown,
          adjustments: adjustments,
          isExpanded: isExpanded
        )
      }
      .buttonStyle(.plain)

      if isExpanded {
        ForEach(adjustments) { adjustment in
          adjustmentCard(adjustment, currency: breakdown.currency)  // swiftlint:disable:this accessibility_trait_for_button line_length
            .onTapGesture {
              adjustmentFormContext = PayrollAdjustmentFormContext(
                breakdown: breakdown,
                jobOptions: displayedBreakdowns.map {
                  PayrollAdjustmentJobOption(id: $0.id, title: $0.title)  // swiftlint:disable:this anonymous_argument_in_multiline_closure line_length
                },
                adjustment: adjustment
              )
            }
        }

        if showsAddButton {
          Button {
            adjustmentFormContext = PayrollAdjustmentFormContext(
              breakdown: breakdown,
              jobOptions: displayedBreakdowns.map {
                PayrollAdjustmentJobOption(id: $0.id, title: $0.title)  // swiftlint:disable:this anonymous_argument_in_multiline_closure line_length
              },
              adjustment: nil
            )
          } label: {
            HStack(spacing: Spacing.xxxs) {
              Image(systemName: "plus")  // swiftlint:disable:this accessibility_label_for_image
                .font(.tidexFootnote)
              Text(.dashboardPayrollDetailsAddAdjustment)
                .font(.tidexLabel)
            }
            .foregroundColor(.tidexTextSecondary)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(Color.tidexBlue.opacity(0.08))  // swiftlint:disable:this no_magic_numbers
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func taxableAdjustmentBreakdownSection(_ breakdown: PayrollCardJobBreakdown) -> some View
  {
    adjustmentBreakdownSection(
      breakdown,
      kind: .taxable,
      adjustments: taxableAdjustments(for: breakdown),
      showsAddButton: onCreateAdjustment != nil
    )
  }

  private func directPayoutAdjustmentBreakdownSection(_ breakdown: PayrollCardJobBreakdown)
    -> some View
  {
    adjustmentBreakdownSection(
      breakdown,
      kind: .directPayout,
      adjustments: directPayoutAdjustments(for: breakdown),
      showsAddButton: onCreateAdjustment != nil && !breakdown.taxEnabled
    )
  }

  private func adjustmentTotalRow(
    _ breakdown: PayrollCardJobBreakdown,
    adjustments: [PayrollAdjustment],
    isExpanded: Bool
  ) -> some View {
    let total = adjustmentTotal(for: adjustments)  // swiftlint:disable:this explicit_type_interface
    return HStack(spacing: Spacing.xs) {
      Text(.dashboardPayrollDetailsAdjustments)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      Image(systemName: "chevron.down")  // swiftlint:disable:this accessibility_label_for_image
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .rotationEffect(.degrees(isExpanded ? 180 : 0))  // swiftlint:disable:this no_magic_numbers

      Spacer()

      Text(total == 0 ? "–" : formatCurrency(total, currency: breakdown.currency))
        .font(.tidexLabel)
        .foregroundColor(total < 0 ? .tidexError : .tidexTextPrimary)
    }
    .contentShape(Rectangle())
  }

  private func supplementBreakdownSection(_ breakdown: PayrollCardJobBreakdown) -> some View {
    VStack(spacing: Spacing.sm) {
      let canExpand = !breakdown.supplementBreakdowns.isEmpty  // swiftlint:disable:this explicit_type_interface
      let isExpanded = expandedSupplementJobIds.contains(breakdown.id)  // swiftlint:disable:this explicit_type_interface

      if canExpand {
        Button {
          withAnimation(.easeInOut(duration: 0.18)) {  // swiftlint:disable:this no_magic_numbers
            if isExpanded {
              expandedSupplementJobIds.remove(breakdown.id)
            } else {
              expandedSupplementJobIds.insert(breakdown.id)
            }
          }
        } label: {
          supplementTotalRow(breakdown, showsChevron: true, isExpanded: isExpanded)
        }
        .buttonStyle(.plain)
      } else {
        supplementTotalRow(breakdown, showsChevron: false, isExpanded: false)
      }

      if canExpand, isExpanded {
        ForEach(breakdown.supplementBreakdowns) { supplement in
          supplementBreakdownCard(supplement, currency: breakdown.currency)
        }
      }
    }
  }

  private func supplementTotalRow(
    _ breakdown: PayrollCardJobBreakdown,
    showsChevron: Bool,
    isExpanded: Bool
  ) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(
        breakdown.supplementBreakdowns.contains(where: \.isOvertime)
          ? .shiftsSupplementsAndOvertime : .shiftsTotalSupplement
      )
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextSecondary)

      if showsChevron {
        Image(systemName: "chevron.down")  // swiftlint:disable:this accessibility_label_for_image
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
          .rotationEffect(.degrees(isExpanded ? 180 : 0))  // swiftlint:disable:this no_magic_numbers
      }

      Spacer()

      Text(formatCurrency(breakdown.supplementPay, currency: breakdown.currency))
        .font(.tidexLabel)
        .foregroundColor(.tidexTextPrimary)
    }
    .contentShape(Rectangle())
  }

  private func supplementBreakdownCard(
    _ supplement: PayrollSupplementBreakdown,
    currency: String
  ) -> some View {
    let segment = supplement.segment  // swiftlint:disable:this explicit_type_interface
    return EarningsSupplementBreakdownDetailCard(
      title: String(
        localized: supplement.isOvertime ? .shiftsOvertimeLabel : .shiftsSupplementLabel),
      timeRange: segment.timeRange,
      hoursAndRate:
        "\(formatHoursValue(supplement.hours)) × \(formatCurrency(supplement.rate, currency: currency))",
      amount: formatCurrency(supplement.amount, currency: currency)
    )
  }

  private func postDeductionBreakdownSection(_ breakdown: PayrollCardJobBreakdown) -> some View {
    VStack(spacing: Spacing.xs) {
      let canExpand = !breakdown.postDeductionParts.isEmpty  // swiftlint:disable:this explicit_type_interface
      let isExpanded = expandedPostDeductionJobIds.contains(breakdown.id)  // swiftlint:disable:this explicit_type_interface

      if canExpand {
        Button {
          withAnimation(.easeInOut(duration: 0.18)) {  // swiftlint:disable:this no_magic_numbers
            if isExpanded {
              expandedPostDeductionJobIds.remove(breakdown.id)
            } else {
              expandedPostDeductionJobIds.insert(breakdown.id)
            }
          }
        } label: {
          postDeductionTotalRow(breakdown, showsChevron: true, isExpanded: isExpanded)
        }
        .buttonStyle(.plain)
      } else {
        postDeductionTotalRow(breakdown, showsChevron: false, isExpanded: false)
      }

      if canExpand, isExpanded {
        ForEach(breakdown.postDeductionParts) { part in
          postDeductionPartCard(part, currency: breakdown.currency)
        }
      }
    }
  }

  private func postDeductionTotalRow(
    _ breakdown: PayrollCardJobBreakdown,
    showsChevron: Bool,
    isExpanded: Bool
  ) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(.shiftsBreakDeduction)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      if showsChevron {
        Image(systemName: "chevron.down")  // swiftlint:disable:this accessibility_label_for_image
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
          .rotationEffect(.degrees(isExpanded ? 180 : 0))  // swiftlint:disable:this no_magic_numbers
      }

      Spacer()

      Text("−\(formatCurrency(breakdown.postDeductions, currency: breakdown.currency))")
        .font(.tidexLabel)
        .foregroundColor(.tidexError)
    }
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func postDeductionPartCard(_ part: BreakDeductionPart, currency: String) -> some View {
    switch part.kind {
    case .base:
      EarningsBreakDeductionDetailCard(
        title: String(localized: .shiftsBreakDeductionPartBasePay),
        amount: "−\(formatCurrency(part.amount, currency: currency))",
        detailTitle: String(localized: .shiftsBreakDeduction),
        detailValue: part.rate.map {
          "\(formatHoursValue(part.hours)) × \(formatCurrency($0, currency: currency))"  // swiftlint:disable:this anonymous_argument_in_multiline_closure line_length
        }
          ?? formatHoursValue(part.hours)
      )

    case .supplement:
      if let segment = part.supplementSegment {
        EarningsBreakDeductionDetailCard(
          title: String(localized: .shiftsBreakDeductionPartSupplement),
          amount: "−\(formatCurrency(part.amount, currency: currency))",
          detailTitle: segment.timeRange,
          detailValue:
            "\(formatHoursValue(part.hours)) × \(formatCurrency(segment.rate, currency: currency))",
          forcesLeftToRight: true
        )
      } else {
        EarningsBreakDeductionDetailCard(
          title: String(localized: .shiftsBreakDeductionPartSupplement),
          amount: "−\(formatCurrency(part.amount, currency: currency))",
          detailTitle:
            "\(formatHoursValue(part.hours)) × \(formatCurrency(part.rate ?? 0, currency: currency))",
          detailValue: nil
        )
      }
    }
  }

  private func adjustmentCard(_ adjustment: PayrollAdjustment, currency: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      EarningsBreakdownDetailCard {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
          Text(adjustmentSubtitle(adjustment))
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)

          Spacer(minLength: Spacing.sm)

          Text(formatCurrency(adjustment.amount, currency: currency))
            .font(.tidexLabelStrong)
            .foregroundColor(adjustment.amount < 0 ? .tidexError : .tidexTextPrimary)
            .lineLimit(1)
            .layoutPriority(1)
        }

        Text(adjustment.description)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.leading)
          .lineLimit(3)  // swiftlint:disable:this no_magic_numbers
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      curatedAdjustmentLink(adjustment)
    }
  }

  @ViewBuilder
  private func curatedAdjustmentLink(_ adjustment: PayrollAdjustment) -> some View {
    if let text = adjustment.curated_note?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    {
      let linkText = adjustment.curated_link?.trimmingCharacters(in: .whitespacesAndNewlines)  // swiftlint:disable:this explicit_type_interface line_length
      let description = adjustment.curated_description?.trimmingCharacters(  // swiftlint:disable:this explicit_type_interface line_length
        in: .whitespacesAndNewlines)  // swiftlint:disable:this multiline_arguments_brackets
      if let description, !description.isEmpty {
        Button {
          curatedAdjustmentContext = PayrollAdjustmentCuratedContext(
            adjustment: adjustment,
            description: description,
            linkURL: linkText.flatMap(URL.init(string:)),
            linkTitle: adjustment.curated_link_title?.trimmingCharacters(
              in: .whitespacesAndNewlines)  // swiftlint:disable:this multiline_arguments_brackets
          )
        } label: {
          curatedAdjustmentText(text)
        }
        .buttonStyle(.plain)
      } else if let linkText, let url = URL(string: linkText) {
        Link(destination: url) {
          curatedAdjustmentText(text)
        }
      } else {
        curatedAdjustmentText(text)
      }
    }
  }

  private func curatedAdjustmentText(_ text: String) -> some View {
    Text(text)
      .font(.tidexFootnote)
      .foregroundColor(.tidexBlue)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, CornerRadius.lg)
      .padding(.bottom, Spacing.xs)
  }

  private func earningsRow(
    label: String,
    value: String,
    valueColor: Color = .tidexTextPrimary,
    isHighlighted: Bool = false
  ) -> some View {
    EarningsBreakdownCard<EmptyView>.Row(
      label: label,
      value: value,
      valueColor: valueColor,
      isHighlighted: isHighlighted
    )
  }

  private func displayAmount(for breakdown: PayrollCardJobBreakdown) -> Double {
    breakdown.taxEnabled ? (breakdown.net ?? breakdown.gross) : breakdown.gross
  }

  private func preDirectPayoutAmount(for breakdown: PayrollCardJobBreakdown) -> Double {
    breakdown.gross - adjustmentTotal(for: directPayoutAdjustments(for: breakdown))
  }

  private func adjustmentTotal(for adjustments: [PayrollAdjustment]) -> Double {
    adjustments.reduce(0) { $0 + $1.amount }
  }

  private func taxableAdjustments(for breakdown: PayrollCardJobBreakdown) -> [PayrollAdjustment] {
    guard breakdown.taxEnabled else { return [] }  // swiftlint:disable:this conditional_returns_on_newline
    return breakdown.adjustments.filter { $0.tax_treatment != .netManual }
  }

  private func directPayoutAdjustments(for breakdown: PayrollCardJobBreakdown)
    -> [PayrollAdjustment]
  {
    guard breakdown.taxEnabled else { return breakdown.adjustments }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return breakdown.adjustments.filter { $0.tax_treatment == .netManual }
  }

  private func adjustmentSectionId(
    _ breakdown: PayrollCardJobBreakdown,
    kind: AdjustmentSectionKind
  ) -> String {
    "\(breakdown.id)-\(kind.rawValue)"
  }

  private func replaceAdjustment(_ adjustment: PayrollAdjustment, in breakdownId: String) {
    var additions = createdAdjustmentsByJobId[breakdownId] ?? []  // swiftlint:disable:this explicit_type_interface
    if let index = additions.firstIndex(where: { $0.id == adjustment.id }) {
      additions[index] = adjustment
      createdAdjustmentsByJobId[breakdownId] = additions
    } else {
      editedAdjustmentsById[adjustment.id] = adjustment
    }
    deletedAdjustmentIds.remove(adjustment.id)
  }

  private func removeAdjustment(_ adjustmentId: String, from breakdownId: String) {
    createdAdjustmentsByJobId[breakdownId, default: []].removeAll { $0.id == adjustmentId }
    editedAdjustmentsById[adjustmentId] = nil
    deletedAdjustmentIds.insert(adjustmentId)
  }

  private func showsTaxDeduction(for breakdown: PayrollCardJobBreakdown) -> Bool {
    breakdown.taxEnabled && (breakdown.tax ?? 0) > 0
  }

  private func adjustmentSubtitle(_ adjustment: PayrollAdjustment) -> String {
    switch adjustment.category {
    case .retroPay:
      return String(localized: .dashboardPayrollDetailsAdjustmentRetroPay)

    case .bonus:
      return String(localized: .dashboardPayrollDetailsAdjustmentBonus)

    case .correction:
      return String(localized: .dashboardPayrollDetailsAdjustmentCorrection)

    case .other:
      return String(localized: .dashboardPayrollDetailsAdjustmentOther)
    }
  }

  private func formatCurrency(_ amount: Double, currency: String) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  private func formatHoursValue(_ hours: Double) -> String {
    ShiftCardFormatter.formattedHours(hours, locale: .appLocale)
  }
}

private struct PayrollAdjustmentJobOption: Identifiable, Equatable {
  let id: String
  let title: String
}

private enum AdjustmentSectionKind: String {
  case taxable  // swiftlint:disable:this explicit_enum_raw_value sorted_enum_cases
  case directPayout  // swiftlint:disable:this explicit_enum_raw_value sorted_enum_cases
}

private struct PayrollAdjustmentFormContext: Identifiable {
  let id = UUID()  // swiftlint:disable:this explicit_type_interface
  let breakdown: PayrollCardJobBreakdown
  let jobOptions: [PayrollAdjustmentJobOption]
  let adjustment: PayrollAdjustment?
}

private struct PayrollAdjustmentCuratedContext: Identifiable {
  let id = UUID()  // swiftlint:disable:this explicit_type_interface
  let adjustment: PayrollAdjustment
  let description: String
  let linkURL: URL?
  let linkTitle: String?
}

private struct PayrollAdjustmentCuratedSheet: View {
  let context: PayrollAdjustmentCuratedContext

  @Environment(\.dismiss) private var dismiss  // swiftlint:disable:this explicit_type_interface

  private var displayLinkTitle: String {
    let trimmed = context.linkTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""  // swiftlint:disable:this explicit_type_interface line_length
    return trimmed.isEmpty
      ? String(localized: .dashboardPayrollDetailsCuratedLinkFallback)
      : trimmed
  }

  var body: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
          Text(context.description)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let linkURL = context.linkURL {
            Link(destination: linkURL) {
              HStack(spacing: Spacing.xxs) {
                Text(displayLinkTitle)
                  .foregroundColor(.tidexBlue)
                Image(systemName: "arrow.up.right")  // swiftlint:disable:this accessibility_label_for_image
                  .font(.tidexFootnote)
                  .foregroundColor(.tidexTextPrimary)
              }
              .font(.tidexLabel)
              .padding(.vertical, Spacing.xs)
              .frame(maxWidth: .infinity)
              .background(Color.tidexBlue.opacity(0.08))  // swiftlint:disable:this no_magic_numbers
              .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
            }
          }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xxl)
      }
      .background(Color.tidexBackground.ignoresSafeArea())
      .navigationTitle(context.adjustment.description)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: .commonDone)) {
            dismiss()
          }
        }
      }
    }
  }
}

private struct PayrollAdjustmentFormSheet: View {  // swiftlint:disable:this type_body_length
  let context: PayrollAdjustmentFormContext  // swiftlint:disable:this type_contents_order
  let onSave: (PayrollAdjustmentDraft) async throws -> Void  // swiftlint:disable:this type_contents_order
  let onDelete: (() async throws -> Void)?  // swiftlint:disable:this type_contents_order

  @Environment(\.dismiss) private var dismiss  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var descriptionText: String  // swiftlint:disable:this type_contents_order
  @State private var amountText = ""  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var category: PayrollAdjustmentCategory = .correction  // swiftlint:disable:this type_contents_order
  @State private var taxTreatment: PayrollAdjustmentTaxTreatment = .grossTaxable  // swiftlint:disable:this line_length type_contents_order
  @State private var note = ""  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var selectedJobId: String?  // swiftlint:disable:this type_contents_order
  @State private var useEarnedRange = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var earnedFromDate: Date  // swiftlint:disable:this type_contents_order
  @State private var earnedToDate: Date  // swiftlint:disable:this type_contents_order
  @State private var isSaving = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var errorMessage: String?  // swiftlint:disable:this type_contents_order
  @FocusState private var focusedField: Field?  // swiftlint:disable:this type_contents_order

  private enum Field {
    case description
    case amount
    case note
  }

  init(  // swiftlint:disable:this type_contents_order
    context: PayrollAdjustmentFormContext,
    onSave: @escaping (PayrollAdjustmentDraft) async throws -> Void,
    onDelete: (() async throws -> Void)? = nil
  ) {
    self.context = context
    self.onSave = onSave
    self.onDelete = onDelete
    let adjustment = context.adjustment  // swiftlint:disable:this explicit_type_interface
    _descriptionText = State(initialValue: adjustment?.description ?? "")
    _amountText = State(initialValue: adjustment.map { String($0.amount) } ?? "")
    _category = State(initialValue: adjustment?.category ?? .correction)
    _taxTreatment = State(
      initialValue: adjustment?.tax_treatment
        ?? (context.breakdown.taxEnabled ? .grossTaxable : .netManual)
    )
    _note = State(initialValue: adjustment?.note ?? "")
    _selectedJobId = State(initialValue: adjustment?.job_id ?? context.breakdown.id)
    let earnedFrom = adjustment?.earned_from_date.flatMap { Date.fromISODateString($0) }  // swiftlint:disable:this explicit_type_interface line_length
    let earnedTo = adjustment?.earned_to_date.flatMap { Date.fromISODateString($0) }  // swiftlint:disable:this explicit_type_interface line_length
    _useEarnedRange = State(initialValue: earnedFrom != nil || earnedTo != nil)
    _earnedFromDate = State(initialValue: earnedFrom ?? context.breakdown.payoutDate)
    _earnedToDate = State(initialValue: earnedTo ?? context.breakdown.payoutDate)
  }

  private var parsedAmount: Double? {
    Double(normalizedAmountText(amountText))
  }

  private var canSave: Bool {
    guard !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    guard let parsedAmount, parsedAmount != 0 else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard !useEarnedRange || earnedFromDate <= earnedToDate else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return !isSaving
  }

  var body: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      Form {  // swiftlint:disable:this closure_body_length
        Section {
          TextField(
            String(localized: .dashboardPayrollDetailsAdjustmentDescriptionPlaceholder),
            text: $descriptionText,
            axis: .vertical
          )
          .textInputAutocapitalization(.sentences)
          .lineLimit(2...4)  // swiftlint:disable:this no_magic_numbers
          .focused($focusedField, equals: .description)

          HStack(spacing: Spacing.sm) {
            TextField(
              String(localized: .dashboardPayrollDetailsAdjustmentAmount), text: $amountText
            )
            .keyboardType(.numbersAndPunctuation)
            .focused($focusedField, equals: .amount)
            .onChange(of: amountText) { _, newValue in
              let sanitized = sanitizedAmountText(newValue)  // swiftlint:disable:this explicit_type_interface
              if sanitized != newValue {
                amountText = sanitized
              }
            }

            if focusedField != .amount, !amountText.isEmpty {
              Text(context.breakdown.currency)
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexTextSecondary)
            }
          }
        }

        Section(String(localized: .dashboardPayrollDetailsAdjustmentCategory)) {
          categoryOption(.retroPay)
          categoryOption(.bonus)
          categoryOption(.correction)
        }

        if context.breakdown.taxEnabled {
          Section(String(localized: .dashboardPayrollDetailsAdjustmentTaxTreatment)) {
            taxTreatmentOption(.grossTaxable)
            taxTreatmentOption(.netManual)
          }
        }

        if context.jobOptions.count > 1 {
          Section {
            Picker(
              String(localized: .dashboardPayrollDetailsAdjustmentJob), selection: $selectedJobId
            ) {
              Text(.dashboardPayrollDetailsAdjustmentNoSpecificJob)
                .tag(String?.none)
              ForEach(context.jobOptions) { job in
                Text(job.title).tag(Optional(job.id))
              }
            }
          }
        }

        Section {
          Toggle(
            String(localized: .dashboardPayrollDetailsAdjustmentUseEarnedRange),
            isOn: $useEarnedRange)  // swiftlint:disable:this multiline_arguments_brackets
          Text(.dashboardPayrollDetailsAdjustmentEarnedRangeHelp)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)

          if useEarnedRange {
            DatePicker(
              String(localized: .dashboardPayrollDetailsAdjustmentEarnedFrom),
              selection: $earnedFromDate,
              displayedComponents: .date
            )
            DatePicker(
              String(localized: .dashboardPayrollDetailsAdjustmentEarnedTo),
              selection: $earnedToDate,
              displayedComponents: .date
            )
          }
        }

        Section {
          TextField(
            String(localized: .dashboardPayrollDetailsAdjustmentNote),
            text: $note,
            axis: .vertical
          )
          .lineLimit(3...8)  // swiftlint:disable:this no_magic_numbers
          .focused($focusedField, equals: .note)
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundColor(.tidexError)
          }
        }

        if onDelete != nil {
          Section {
            Button(role: .destructive) {
              delete()
            } label: {
              Text(.commonDelete)
            }
            .disabled(isSaving)
          }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(
        String(
          localized: context.adjustment == nil
            ? .dashboardPayrollDetailsAddAdjustment
            : .dashboardPayrollDetailsEditAdjustment
        )
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .disabled(isSaving)
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonSave)) {
            save()
          }
          .disabled(!canSave)
        }

        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(String(localized: .commonDone)) {
            dismissKeyboard()
          }
        }
      }
    }
  }

  private func save() {
    guard let parsedAmount else { return }  // swiftlint:disable:this conditional_returns_on_newline
    isSaving = true
    errorMessage = nil

    let draft = PayrollAdjustmentDraft(  // swiftlint:disable:this explicit_type_interface
      jobId: selectedJobId,
      amount: parsedAmount,
      currency: context.breakdown.currency,
      category: category,
      taxTreatment: context.breakdown.taxEnabled ? taxTreatment : .netManual,
      description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
      note: normalizedNote(),
      earnedFromDate: useEarnedRange ? earnedFromDate : nil,
      earnedToDate: useEarnedRange ? earnedToDate : nil,
      payoutDate: context.breakdown.payoutDate
    )

    Task {
      do {
        try await onSave(draft)
        await MainActor.run {
          isSaving = false
          dismiss()
        }
      } catch {
        await MainActor.run {
          isSaving = false
          errorMessage = String(localized: .dashboardPayrollDetailsAdjustmentSaveFailed)
        }
      }
    }
  }

  private func delete() {
    guard let onDelete else { return }  // swiftlint:disable:this conditional_returns_on_newline
    isSaving = true
    errorMessage = nil

    Task {
      do {
        try await onDelete()
        await MainActor.run {
          isSaving = false
          dismiss()
        }
      } catch {
        await MainActor.run {
          isSaving = false
          errorMessage = String(localized: .dashboardPayrollDetailsAdjustmentSaveFailed)
        }
      }
    }
  }

  private func label(for category: PayrollAdjustmentCategory) -> String {
    switch category {
    case .retroPay:
      return String(localized: .dashboardPayrollDetailsAdjustmentRetroPay)

    case .bonus:
      return String(localized: .dashboardPayrollDetailsAdjustmentBonus)

    case .correction:
      return String(localized: .dashboardPayrollDetailsAdjustmentCorrection)

    case .other:
      return String(localized: .dashboardPayrollDetailsAdjustmentOther)
    }
  }

  private func categoryOption(_ option: PayrollAdjustmentCategory) -> some View {
    Button {
      category = option
    } label: {
      HStack {
        Text(label(for: option))
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
        Spacer()
        if category == option {
          Image(systemName: "checkmark")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func label(for taxTreatment: PayrollAdjustmentTaxTreatment) -> String {
    switch taxTreatment {
    case .grossTaxable:
      return String(localized: .dashboardPayrollDetailsAdjustmentGrossTaxable)

    case .netManual:
      return String(localized: .dashboardPayrollDetailsAdjustmentNetManual)

    case .excludedFromTaxEstimate:
      return String(localized: .dashboardPayrollDetailsAdjustmentExcludedFromTax)
    }
  }

  private func helpText(for taxTreatment: PayrollAdjustmentTaxTreatment) -> String {
    taxTreatment == .grossTaxable
      ? String(localized: .dashboardPayrollDetailsAdjustmentGrossTaxableHelp)
      : String(localized: .dashboardPayrollDetailsAdjustmentNetManualHelp)
  }

  private func taxTreatmentOption(_ option: PayrollAdjustmentTaxTreatment) -> some View {
    Button {
      taxTreatment = option
    } label: {
      HStack(alignment: .top, spacing: Spacing.sm) {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
          Text(label(for: option))
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text(helpText(for: option))
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        if taxTreatment == option {
          Image(systemName: "checkmark")  // swiftlint:disable:this accessibility_label_for_image
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func normalizedNote() -> String? {
    let trimmed: String = note.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func sanitizedAmountText(_ value: String) -> String {
    var result = ""  // swiftlint:disable:this explicit_type_interface
    var hasDecimalSeparator = false  // swiftlint:disable:this explicit_type_interface

    for character in value {
      if character.isNumber {
        result.append(character)
      } else if character == "-" {
        if result.isEmpty {
          result.append(character)
        }
      } else if character == "." || character == "," {
        if !hasDecimalSeparator {
          result.append(character)
          hasDecimalSeparator = true
        }
      }
    }

    return result
  }

  private func normalizedAmountText(_ value: String) -> String {
    value
      .replacingOccurrences(of: ",", with: ".")
  }

  private func dismissKeyboard() {
    focusedField = nil
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}

extension PayrollCardJobBreakdown {
  fileprivate func withAdjustments(_ nextAdjustments: [PayrollAdjustment])  // swiftlint:disable:this strict_fileprivate
    -> PayrollCardJobBreakdown
  {
    let originalTotals = adjustmentDisplayTotals(adjustments)  // swiftlint:disable:this explicit_type_interface
    let nextTotals = adjustmentDisplayTotals(nextAdjustments)  // swiftlint:disable:this explicit_type_interface
    let grossDelta = nextTotals.gross - originalTotals.gross  // swiftlint:disable:this explicit_type_interface
    let netDelta = nextTotals.net - originalTotals.net  // swiftlint:disable:this explicit_type_interface

    return PayrollCardJobBreakdown(
      id: id,
      title: title,
      colorHex: colorHex,
      currency: currency,
      basePay: basePay,
      supplementPay: supplementPay,
      supplementBreakdowns: supplementBreakdowns,
      postDeductions: postDeductions,
      postDeductionParts: postDeductionParts,
      payoutDate: payoutDate,
      gross: gross + grossDelta,
      net: net.map { $0 + netDelta },
      tax: tax,
      taxEnabled: taxEnabled,
      adjustments: nextAdjustments
    )
  }

  private func adjustmentDisplayTotals(_ adjustments: [PayrollAdjustment]) -> (
    gross: Double, net: Double
  ) {
    adjustments.reduce((gross: 0, net: 0)) { total, adjustment in
      var next = total  // swiftlint:disable:this explicit_type_interface
      guard taxEnabled else {
        next.gross += adjustment.amount
        next.net += adjustment.amount
        return next
      }
      switch adjustment.tax_treatment {
      case .grossTaxable, .excludedFromTaxEstimate:
        next.gross += adjustment.amount
        next.net += adjustment.amount

      case .netManual:
        next.net += adjustment.amount
      }
      return next
    }
  }
}  // swiftlint:disable:this file_length
