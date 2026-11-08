import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

extension DashboardViewModel {

  func isCurrentMonthAdvancedNextPayoutDate(  // swiftlint:disable:this explicit_acl type_contents_order
    _ payoutDate: Date,
    now: Date = Date()
  ) -> Bool {
    let current = now.yearMonth()  // swiftlint:disable:this explicit_type_interface
    let jobs = currentPayrollSelectionJobs()  // swiftlint:disable:this explicit_type_interface
    guard !jobs.isEmpty else { return false }  // swiftlint:disable:this conditional_returns_on_newline

    let fallbackPayrollDay = settings?.effectivePayrollDay ?? 15  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    guard
      let currentSelection = DashboardPayrollSelector.select(
        displayYM: current,
        jobs: sortedPayrollSelectionJobs(jobs, displayYM: current),
        fallbackPayrollDay: fallbackPayrollDay,
        isViewingCurrentMonth: true,
        now: now
      )
    else {
      return false
    }

    guard
      currentSelection.payoutYear != current.year
        || currentSelection.payoutMonth != current.month
    else {
      return false
    }

    return Calendar.gregorianCurrent.isDate(currentSelection.payoutDate, inSameDayAs: payoutDate)
  }

  func currentPayrollProgressStartDate(  // swiftlint:disable:this explicit_acl type_contents_order
    for payoutDate: Date,
    now: Date = Date()
  ) -> Date? {
    let current = now.yearMonth()  // swiftlint:disable:this explicit_type_interface
    let jobs = currentPayrollSelectionJobs()  // swiftlint:disable:this explicit_type_interface
    guard !jobs.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    let fallbackPayrollDay = settings?.effectivePayrollDay ?? 15  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    let sortedJobs = sortedPayrollSelectionJobs(jobs, displayYM: current)  // swiftlint:disable:this explicit_type_interface line_length
    let selections = DashboardPayrollSelector.selections(  // swiftlint:disable:this explicit_type_interface
      displayYM: current,
      jobs: sortedJobs,
      fallbackPayrollDay: fallbackPayrollDay,
      isViewingCurrentMonth: true,
      now: now
    )

    guard
      let selection = selections.first(where: {
        Calendar.gregorianCurrent.isDate($0.payoutDate, inSameDayAs: payoutDate)  // swiftlint:disable:this anonymous_argument_in_multiline_closure line_length
      })
    else {
      return nil
    }

    return DashboardPayrollSelector.previousPayoutStartDate(
      for: selection,
      jobs: sortedJobs,
      fallbackPayrollDay: fallbackPayrollDay
    )
  }

  func payrollCardVariants(  // swiftlint:disable:this explicit_acl type_contents_order
    fallback: DashboardData,
    defaultTitle: String
  ) -> [PayrollCardVariant] {
    let matchingSnapshot = payrollCardSnapshot.flatMap { snapshot in  // swiftlint:disable:this explicit_type_interface
      snapshot.displayedYear == fallback.displayedYear
        && snapshot.displayedMonth == fallback.displayedMonth
        ? snapshot
        : nil
    }
    let variants =  // swiftlint:disable:this explicit_type_interface
      matchingSnapshot?.variants
      ?? Self.fallbackPayrollCardVariants(fallback: fallback)
    return variants.map { $0.resolvingDefaultTitle(defaultTitle) }
  }

  func previousPayrollCardVariants(  // swiftlint:disable:this explicit_acl type_contents_order
    fallback: DashboardData,
    defaultTitle: String
  ) -> [PayrollCardVariant] {
    guard
      let snapshot = payrollCardSnapshot,
      snapshot.displayedYear == fallback.displayedYear,
      snapshot.displayedMonth == fallback.displayedMonth
    else {
      return []
    }

    return snapshot.previousPayoutVariants.map { $0.resolvingDefaultTitle(defaultTitle) }
  }

  nonisolated private static func fallbackPayrollCardVariants(  // swiftlint:disable:this type_contents_order
    fallback: DashboardData
  ) -> [PayrollCardVariant] {
    [
      PayrollCardVariant(
        id: "default",
        title: "",
        colorHex: nil,
        usesDefaultTitle: true,
        badges: [],
        currency: fallback.currency,
        payoutDate: fallback.payrollDate,
        gross: fallback.previousMonthGross,
        net: fallback.previousMonthNet,
        tax: fallback.previousMonthTax,
        taxEnabled: fallback.previousMonthTaxEnabled,
        hasPayrollAdjustments: fallback.previousMonthHasPayrollAdjustments,
        jobBreakdowns: []
      )
    ]
  }

  nonisolated private static func buildPayrollCardVariants(  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    _ input: PayrollCardVariantBuildInput,
    defaultTitle: String = "",
    selectionMode: PayrollCardVariantSelectionMode = .primary
  ) -> [PayrollCardVariant] {
    let displayedMonthShifts = input.displayedMonthShifts  // swiftlint:disable:this explicit_type_interface
    let previousMonthShifts = input.previousMonthShifts  // swiftlint:disable:this explicit_type_interface
    // The next payout can include next month's shifts or reach two months back.
    let payoutShiftPool =
      displayedMonthShifts + previousMonthShifts + input.earlierMonthShifts + input.nextMonthShifts
    let payrollAdjustmentsByPayoutMonth = input.payrollAdjustmentsByPayoutMonth  // swiftlint:disable:this explicit_type_interface line_length
    let previousPayrollAdjustments = input.previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
    let snapshots = input.snapshots  // swiftlint:disable:this explicit_type_interface
    let settings = input.settings  // swiftlint:disable:this explicit_type_interface
    let jobs = input.jobs  // swiftlint:disable:this explicit_type_interface
    let displayYM = input.displayYM  // swiftlint:disable:this explicit_type_interface
    let fallbackCurrency = input.fallbackCurrency  // swiftlint:disable:this explicit_type_interface
    let fallbackPayrollDate = input.fallbackPayrollDate  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousGross = input.fallbackPreviousGross  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousNet = input.fallbackPreviousNet  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousTax = input.fallbackPreviousTax  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousTaxEnabled = input.fallbackPreviousTaxEnabled  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousHasPayrollAdjustments = input.fallbackPreviousHasPayrollAdjustments  // swiftlint:disable:this explicit_type_interface line_length
    let now = input.now  // swiftlint:disable:this explicit_type_interface

    func fallbackVariant() -> [PayrollCardVariant] {
      [
        PayrollCardVariant(
          id: "default",
          title: defaultTitle,
          colorHex: nil,
          usesDefaultTitle: true,
          badges: [],
          currency: fallbackCurrency,
          payoutDate: fallbackPayrollDate,
          gross: fallbackPreviousGross,
          net: fallbackPreviousNet,
          tax: fallbackPreviousTax,
          taxEnabled: fallbackPreviousTaxEnabled,
          hasPayrollAdjustments: fallbackPreviousHasPayrollAdjustments,
          jobBreakdowns: []
        )
      ]
    }

    guard let settings, !jobs.isEmpty else {
      return selectionMode == .primary ? fallbackVariant() : []
    }

    let fallbackPayrollDay = settings.effectivePayrollDay  // swiftlint:disable:this explicit_type_interface
    let halfTaxMonth = settings.half_tax_month  // swiftlint:disable:this explicit_type_interface
    let defaultJobId = jobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    let sortedJobs = sortedPayrollSelectionJobs(  // swiftlint:disable:this explicit_type_interface
      jobs,
      displayYM: displayYM,
      fallbackPayrollDay: fallbackPayrollDay
    )

    let current = now.yearMonth()  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth =  // swiftlint:disable:this explicit_type_interface
      displayYM.year == current.year && displayYM.month == current.month
    let candidateSelections: [DashboardPayrollSelection] = {
      switch selectionMode {
      case .primary:
        return DashboardPayrollSelector.selections(
          displayYM: displayYM,
          jobs: sortedJobs,
          fallbackPayrollDay: fallbackPayrollDay,
          isViewingCurrentMonth: isViewingCurrentMonth,
          now: now
        )

      case .previousPassedCurrentMonth:
        guard isViewingCurrentMonth else { return [] }  // swiftlint:disable:this conditional_returns_on_newline
        return DashboardPayrollSelector.previousPassedSelections(
          displayYM: displayYM,
          jobs: sortedJobs,
          fallbackPayrollDay: fallbackPayrollDay,
          now: now
        )
      }
    }()

    let candidateJobVariantGroups = candidateSelections.map { selection in  // swiftlint:disable:this closure_body_length explicit_type_interface line_length
      let selectedJobIds = Set(selection.jobIds)  // swiftlint:disable:this explicit_type_interface
      let selectedJobs = sortedJobs.filter { selectedJobIds.contains($0.id) }  // swiftlint:disable:this explicit_type_interface line_length
      let payoutYM = (year: selection.payoutYear, month: selection.payoutMonth)  // swiftlint:disable:this explicit_type_interface line_length
      let selectedPayoutAdjustments = payrollAdjustments(  // swiftlint:disable:this explicit_type_interface
        forPayoutYM: (year: selection.payoutYear, month: selection.payoutMonth),
        renderedDisplayYM: displayYM,
        payrollAdjustmentsByPayoutMonth: payrollAdjustmentsByPayoutMonth,
        previousPayrollAdjustments: previousPayrollAdjustments
      )
      let payoutDate = selection.payoutDate  // swiftlint:disable:this explicit_type_interface

      return selectedJobs.compactMap { job -> PayrollCardVariant? in  // swiftlint:disable:this closure_body_length
        guard let window = selection.windowsByJobId[job.id] else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
        let schedule = PayoutSchedule(job: job, fallbackPayrollDay: fallbackPayrollDay)  // swiftlint:disable:this explicit_type_interface line_length
        let jobShifts = payoutShiftPool.filter { shift in  // swiftlint:disable:this explicit_type_interface
          guard window.contains(shift.shiftDate) else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
          guard let shiftJobId = shift.shift.job_id else {
            return job.id == defaultJobId
          }
          return shiftJobId == job.id
        }

        let totals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
          shifts: jobShifts,
          halfTaxMonth: job.half_tax_month,
          earningsMonth: Date.previousYearMonth(from: payoutYM).month,
          now: now
        )
        let jobPaydaysInMonth =
          schedule  // swiftlint:disable:this explicit_type_interface
          .windows(paidInYear: payoutYM.year, month: payoutYM.month)
          .map(\.adjustedPayoutDate)
        let jobAdjustments = selectedPayoutAdjustments.filter { adjustment in  // swiftlint:disable:this explicit_type_interface line_length
          guard
            DashboardPayrollAdjustmentFilter.matches(
              adjustment, payoutDate: payoutDate, jobPayoutDatesInMonth: jobPaydaysInMonth)
          else {
            return false
          }
          guard let adjustmentJobId = adjustment.job_id else {
            return job.id == defaultJobId
          }
          return adjustmentJobId == job.id
        }
        let fallbackTaxSettings = payrollTaxSettings(  // swiftlint:disable:this explicit_type_interface
          from: jobShifts,
          fallbackDate: window.payoutDate,
          snapshots: snapshots,
          jobs: jobs,
          jobId: job.id
        )
        let adjustmentTotals = PayrollAdjustmentCalculator.totals(  // swiftlint:disable:this explicit_type_interface
          adjustments: jobAdjustments,
          taxSettings: { adjustment in
            payrollTaxSettings(
              for: adjustment,
              fallback: fallbackTaxSettings,
              snapshots: snapshots,
              jobs: jobs,
              jobId: job.id,
              defaultJobId: defaultJobId
            )
          },
          halfTaxMonth: halfTaxMonth,
          payoutMonth: selection.payoutMonth,
          jobs: jobs
        )
        let taxEnabled: Bool =
          jobShifts.contains(where: \.taxEnabled) || adjustmentTotals.taxEnabled
        let shiftBasePay = jobShifts.reduce(0) { total, shift in  // swiftlint:disable:this explicit_type_interface
          total + displayedBasePay(for: shift)
        }
        let shiftSupplementPay: Double = jobShifts.reduce(0) { total, shift in
          total + displayedSupplementPay(for: shift)
        }
        let supplementBreakdowns: [PayrollSupplementBreakdown] = payrollSupplementBreakdowns(
          for: jobShifts
        )
        let shiftPostDeductions = jobShifts.reduce(0) { total, shift in  // swiftlint:disable:this explicit_type_interface line_length
          total + breakDeductionAmount(for: shift)
        }
        let postDeductionParts = payrollBreakDeductionParts(for: jobShifts)  // swiftlint:disable:this explicit_type_interface line_length
        let gross = totals.gross + adjustmentTotals.gross  // swiftlint:disable:this explicit_type_interface
        let net = totals.net + adjustmentTotals.net  // swiftlint:disable:this explicit_type_interface
        let tax = taxEnabled ? gross - net : nil  // swiftlint:disable:this explicit_type_interface

        return PayrollCardVariant(
          id: job.id,
          title: job.name,
          colorHex: job.color,
          badges: [
            PayrollCardBadge(
              id: job.id,
              title: job.name,
              colorHex: job.color
            )
          ],
          currency: job.currency,
          payoutDate: payoutDate,
          gross: gross,
          net: taxEnabled ? net : nil,
          tax: tax,
          taxEnabled: taxEnabled,
          hasPayrollAdjustments: !jobAdjustments.isEmpty,
          jobBreakdowns: [
            PayrollCardJobBreakdown(
              id: job.id,
              title: job.name,
              colorHex: job.color,
              currency: job.currency,
              basePay: shiftBasePay,
              supplementPay: shiftSupplementPay,
              supplementBreakdowns: supplementBreakdowns,
              postDeductions: shiftPostDeductions,
              postDeductionParts: postDeductionParts,
              payoutDate: payoutDate,
              gross: gross,
              net: taxEnabled ? net : nil,
              tax: tax,
              taxEnabled: taxEnabled,
              adjustments: jobAdjustments,
              earningsPeriodStart: Date.fromISODateString(window.start),
              earningsPeriodEnd: Date.fromISODateString(window.end),
              payoutTaxSettings: fallbackTaxSettings.adjusted(
                payoutMonth: selection.payoutMonth, halfTaxMonth: job.half_tax_month)
            )
          ]
        )
      }
    }

    let selectedPayoutJobs =  // swiftlint:disable:this explicit_type_interface
      DashboardPayrollVariantPicker.firstPayableVariants(in: candidateJobVariantGroups)
      ?? candidateJobVariantGroups.first { !$0.isEmpty }

    guard let selectedPayoutJobs, let payoutDate = selectedPayoutJobs.first?.payoutDate else {
      return selectionMode == .primary ? fallbackVariant() : []
    }

    guard selectedPayoutJobs.count > 1 else {
      guard let selectedPayoutJob = selectedPayoutJobs.first else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
      let usesDefaultTitle = jobs.count <= 1  // swiftlint:disable:this explicit_type_interface
      return [
        PayrollCardVariant(
          id: selectedPayoutJob.id,
          title: usesDefaultTitle ? defaultTitle : selectedPayoutJob.title,
          colorHex: usesDefaultTitle ? nil : selectedPayoutJob.colorHex,
          usesDefaultTitle: usesDefaultTitle,
          badges: usesDefaultTitle ? [] : selectedPayoutJob.badges,
          currency: selectedPayoutJob.currency,
          payoutDate: selectedPayoutJob.payoutDate,
          gross: selectedPayoutJob.gross,
          net: selectedPayoutJob.net,
          tax: selectedPayoutJob.tax,
          taxEnabled: selectedPayoutJob.taxEnabled,
          hasPayrollAdjustments: selectedPayoutJob.hasPayrollAdjustments,
          jobBreakdowns: selectedPayoutJob.jobBreakdowns
        )
      ]
    }

    let taxEnabled = selectedPayoutJobs.contains(where: \.taxEnabled)  // swiftlint:disable:this explicit_type_interface
    let gross = selectedPayoutJobs.reduce(0) { $0 + $1.gross }  // swiftlint:disable:this explicit_type_interface
    // swiftlint:disable:next explicit_type_interface
    let net = selectedPayoutJobs.reduce(0) { $0 + ($1.net ?? $1.gross) }
    let tax = taxEnabled ? gross - net : nil  // swiftlint:disable:this explicit_type_interface

    return [
      PayrollCardVariant(
        id: "payout-\(payoutDate.timeIntervalSince1970)",
        title: defaultTitle,
        colorHex: nil,
        usesDefaultTitle: true,
        badges: selectedPayoutJobs.flatMap(\.badges),
        currency: selectedPayoutJobs.first?.currency ?? fallbackCurrency,
        payoutDate: payoutDate,
        gross: gross,
        net: taxEnabled ? net : nil,
        tax: tax,
        taxEnabled: taxEnabled,
        hasPayrollAdjustments: selectedPayoutJobs.contains(where: \.hasPayrollAdjustments),
        jobBreakdowns: selectedPayoutJobs.flatMap(\.jobBreakdowns)
      )
    ]
  }

  nonisolated static func buildPayrollCardSnapshot(  // swiftlint:disable:this type_contents_order
    _ input: PayrollCardVariantBuildInput
  ) -> DashboardPayrollCardSnapshot {
    DashboardPayrollCardSnapshot(
      displayedYear: input.displayYM.year,
      displayedMonth: input.displayYM.month,
      variants: buildPayrollCardVariants(input),
      previousPayoutVariants: buildPayrollCardVariants(
        input,
        defaultTitle: String(localized: .dashboardPreviousPayout),
        selectionMode: .previousPassedCurrentMonth
      )
    )
  }

  func createPayrollAdjustment(  // swiftlint:disable:this explicit_acl type_contents_order
    _ draft: PayrollAdjustmentDraft
  ) async throws -> PayrollAdjustment {
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    let adjustment = try await payrollAdjustmentsRepository.createAdjustment(  // swiftlint:disable:this explicit_type_interface line_length
      userId: userId,
      jobId: draft.jobId,
      amount: draft.amount,
      currency: draft.currency,
      category: draft.category,
      taxTreatment: draft.taxTreatment,
      description: draft.description,
      note: draft.note,
      earnedFromDate: draft.earnedFromDate,
      earnedToDate: draft.earnedToDate,
      payoutDate: draft.payoutDate
    )

    await loadDashboardFromLocal(showLoadingState: false)
    return adjustment
  }

  func updatePayrollAdjustment(_ id: String, _ draft: PayrollAdjustmentDraft) async throws  // swiftlint:disable:this explicit_acl line_length type_contents_order
    -> PayrollAdjustment
  {
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    let adjustment = try await payrollAdjustmentsRepository.updateAdjustment(  // swiftlint:disable:this explicit_type_interface line_length
      id: id,
      userId: userId,
      jobId: draft.jobId,
      amount: draft.amount,
      currency: draft.currency,
      category: draft.category,
      taxTreatment: draft.taxTreatment,
      description: draft.description,
      note: draft.note,
      earnedFromDate: draft.earnedFromDate,
      earnedToDate: draft.earnedToDate,
      payoutDate: draft.payoutDate
    )

    await loadDashboardFromLocal(showLoadingState: false)
    return adjustment
  }

  func deletePayrollAdjustment(id: String) async throws {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    try await payrollAdjustmentsRepository.deleteAdjustment(id: id, userId: userId)
    await loadDashboardFromLocal(showLoadingState: false)
  }

  /// Resolve a stable user ID for payroll card variants while reload is in-flight.
  /// This prevents a transient fallback to single-card UI during `cachedUserId` resets.
  func resolveUserIdForPayrollVariants() -> String? {  // swiftlint:disable:this type_contents_order
    if let cachedUserId, !cachedUserId.isEmpty {
      return cachedUserId
    }

    if let settingsUserId = settings?.user_id, !settingsUserId.isEmpty {
      return settingsUserId
    }

    if let coordinatorUserId = AppCoordinator.shared.getCurrentUserId(), !coordinatorUserId.isEmpty
    {
      return coordinatorUserId
    }

    return nil
  }

  private func currentPayrollSelectionJobs() -> [Job] {  // swiftlint:disable:this type_contents_order
    if !displayJobs.isEmpty {
      return displayJobs
    }

    guard let userId = resolveUserIdForPayrollVariants() else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return jobsRepository.getNonDeletedJobs(for: userId)
  }

  private func sortedPayrollSelectionJobs(  // swiftlint:disable:this type_contents_order
    _ jobs: [Job],
    displayYM: (year: Int, month: Int)
  ) -> [Job] {
    let fallbackPayrollDay = settings?.effectivePayrollDay ?? 15  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers

    return Self.sortedPayrollSelectionJobs(
      jobs,
      displayYM: displayYM,
      fallbackPayrollDay: fallbackPayrollDay
    )
  }

  nonisolated private static func sortedPayrollSelectionJobs(  // swiftlint:disable:this type_contents_order
    _ jobs: [Job],
    displayYM: (year: Int, month: Int),
    fallbackPayrollDay: Int
  ) -> [Job] {
    jobs.sorted { lhs, rhs in
      let lhsPayout = PayrollDateAdjuster.adjustPayrollDate(  // swiftlint:disable:this explicit_type_interface
        payrollDay: lhs.payroll_day ?? fallbackPayrollDay,
        month: displayYM.month,
        year: displayYM.year
      )
      let rhsPayout = PayrollDateAdjuster.adjustPayrollDate(  // swiftlint:disable:this explicit_type_interface
        payrollDay: rhs.payroll_day ?? fallbackPayrollDay,
        month: displayYM.month,
        year: displayYM.year
      )

      if lhsPayout == rhsPayout {
        if lhs.sort_order == rhs.sort_order {
          return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        return lhs.sort_order < rhs.sort_order
      }

      return lhsPayout < rhsPayout
    }
  }

  nonisolated private static func payrollAdjustments(  // swiftlint:disable:this type_contents_order
    forPayoutYM payoutYM: (year: Int, month: Int),
    renderedDisplayYM displayYM: (year: Int, month: Int),
    payrollAdjustmentsByPayoutMonth: [PayrollReadMonth: [PayrollAdjustment]],
    previousPayrollAdjustments: [PayrollAdjustment]
  ) -> [PayrollAdjustment] {
    let key = PayrollReadMonth(year: payoutYM.year, month: payoutYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    if let adjustments = payrollAdjustmentsByPayoutMonth[key] {
      return adjustments
    }

    if payoutYM.year == displayYM.year, payoutYM.month == displayYM.month {
      return previousPayrollAdjustments
    }

    return []
  }

  nonisolated private static func displayedBasePay(  // swiftlint:disable:this type_contents_order
    for shift: ShiftWithComputations
  ) -> Double {
    breakDeductionAmount(for: shift) > 0
      ? BreakDeductionBreakdown.basePay(for: shift.computed.preBreakWagePeriods)
      : shift.computed.basePay
  }

  nonisolated private static func displayedSupplementPay(  // swiftlint:disable:this type_contents_order
    for shift: ShiftWithComputations
  ) -> Double {
    breakDeductionAmount(for: shift) > 0
      ? BreakDeductionBreakdown.supplementPay(for: shift.computed.preBreakWagePeriods)
      : shift.computed.supplementPay
  }

  nonisolated private static func breakDeductionAmount(  // swiftlint:disable:this type_contents_order
    for shift: ShiftWithComputations
  ) -> Double {
    guard shift.computed.breakAudit.deductedHours > 0 else {
      return 0
    }
    return BreakDeductionBreakdown.make(
      originalPeriods: shift.computed.preBreakWagePeriods,
      adjustedPeriods: shift.computed.wagePeriods
    )?.totalAmount ?? 0
  }

  nonisolated private static func payrollBreakDeductionParts(for shifts: [ShiftWithComputations])  // swiftlint:disable:this function_body_length line_length type_contents_order
    -> [BreakDeductionPart]
  {
    let parts = shifts.flatMap { shift -> [BreakDeductionPart] in  // swiftlint:disable:this explicit_type_interface
      guard shift.computed.breakAudit.deductedHours > 0 else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
      return BreakDeductionBreakdown.make(
        originalPeriods: shift.computed.preBreakWagePeriods,
        adjustedPeriods: shift.computed.wagePeriods
      )?.parts ?? []
    }

    var grouped: [String: BreakDeductionPart] = [:]

    for part in parts {
      let key: String
      switch part.kind {
      case .base:
        key = "base"

      case .supplement:
        key = "supplement-\(part.supplementSegment?.id ?? "\(part.rate ?? 0)")"
      }

      if let existing = grouped[key] {
        let hours = existing.hours + part.hours  // swiftlint:disable:this explicit_type_interface
        let amount = existing.amount + part.amount  // swiftlint:disable:this explicit_type_interface
        grouped[key] = BreakDeductionPart(
          id: key,
          kind: existing.kind,
          supplementSegment: existing.supplementSegment.map {
            SupplementSegment(
              fromMin: $0.fromMin,  // swiftlint:disable:this anonymous_argument_in_multiline_closure
              toMin: $0.toMin,  // swiftlint:disable:this anonymous_argument_in_multiline_closure
              rate: $0.rate,  // swiftlint:disable:this anonymous_argument_in_multiline_closure
              actualHours: hours
            )
          },
          hours: hours,
          rate: hours > 0 ? amount / hours : existing.rate,
          amount: amount
        )
      } else {
        grouped[key] = BreakDeductionPart(
          id: key,
          kind: part.kind,
          supplementSegment: part.supplementSegment,
          hours: part.hours,
          rate: part.rate,
          amount: part.amount
        )
      }
    }

    return grouped.values.sorted { lhs, rhs in
      if lhs.kind != rhs.kind {
        return lhs.kind == .base
      }
      return lhs.id < rhs.id
    }
  }

  nonisolated private static func payrollSupplementBreakdowns(for shifts: [ShiftWithComputations])
    -> [PayrollSupplementBreakdown]
  {
    let segments = shifts.flatMap { shift -> [SupplementSegment] in
      let periods =
        shift.computed.breakAudit.deductedHours > 0
        ? shift.computed.preBreakWagePeriods : shift.computed.classifiedWagePeriods
      return SupplementSegment.grouped(from: periods)
    }

    let grouped = segments.reduce(  // swiftlint:disable:this explicit_type_interface
      into: [
        String: (fromMin: Double, toMin: Double, rate: Double, hours: Double, isOvertime: Bool)
      ]()
    ) { result, segment in
      let key = segment.id  // swiftlint:disable:this explicit_type_interface
      result[key, default: (segment.fromMin, segment.toMin, segment.rate, 0, segment.isOvertime)]
        .hours +=
        segment.actualHours
    }

    return grouped.values.map { segment in
      PayrollSupplementBreakdown(
        fromMin: segment.fromMin,
        toMin: segment.toMin,
        rate: segment.rate,
        hours: segment.hours,
        amount: segment.hours * segment.rate,
        isOvertime: segment.isOvertime
      )
    }
    .sorted { lhs, rhs in
      if lhs.fromMin == rhs.fromMin {
        if lhs.toMin == rhs.toMin {
          return lhs.rate < rhs.rate
        }
        return lhs.toMin < rhs.toMin
      }
      return lhs.fromMin < rhs.fromMin
    }
  }

  /// Prepare for reload by setting loading state synchronously
  /// Call this BEFORE starting a Task to reload, to prevent empty state flash
  /// This ensures the loading indicator shows immediately when sync completes
  func prepareForReload() {  // swiftlint:disable:this explicit_acl type_contents_order
    isLoading = true
  }

  /// Returns whether payroll has been manually marked as received for the displayed month.
  func isPayrollReceivedOverrideForDisplayedMonth(userId: String? = nil) -> Bool {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else {
      return false
    }
    if !payrollReceivedOverrideKeys.contains(key), UserDefaults.standard.bool(forKey: key) {
      payrollReceivedOverrideKeys.insert(key)
    }
    return payrollReceivedOverrideKeys.contains(key)
  }

  /// Marks payroll as received for the displayed month.
  /// This is idempotent and only stores `true`.
  func markPayrollReceivedForDisplayedMonth(userId: String? = nil) {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    UserDefaults.standard.set(true, forKey: key)
    payrollReceivedOverrideKeys.insert(key)
  }

  /// Clears the manual payroll-received override for the displayed month.
  func clearPayrollReceivedOverrideForDisplayedMonth(userId: String? = nil) {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    UserDefaults.standard.removeObject(forKey: key)
    payrollReceivedOverrideKeys.remove(key)
  }

  // MARK: - Payroll Override Helpers

  private func payrollReceivedOverrideKeyForDisplayedMonth(userId: String? = nil) -> String? {  // swiftlint:disable:this line_length type_contents_order
    let resolvedUserId = userId ?? cachedUserId  // swiftlint:disable:this explicit_type_interface
    guard let resolvedUserId, !resolvedUserId.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return "dashboard.payroll.received.\(resolvedUserId).\(displayYearMonthKey)"
  }

  private var displayYearMonthKey: String {
    String(format: "%04d-%02d", displayYear, displayMonth)
  }

  // MARK: - Helper Methods

  static func timeString(from date: Date) -> String {
    ClockSessionRules.timeString(from: date)
  }

  static func isShiftOngoing(_ shift: ShiftRow, at date: Date) -> Bool {
    ClockSessionRules.isShiftOngoing(shift, at: date)
  }

  /// Calculate the adjusted payroll date for a given month
  /// Adjusts backwards if the date falls on a weekend, Monday, or Norwegian public holiday
  func calculatePayrollDate(year: Int, month: Int, day: Int) -> Date {
    return PayrollDateAdjuster.adjustPayrollDate(payrollDay: day, month: month, year: year)
  }

  func monthName(year: Int, month: Int) -> String {
    var components = DateComponents()  // swiftlint:disable:this explicit_type_interface
    components.year = year
    components.month = month
    components.day = 1
    guard let date = Self.gregorianCalendar.date(from: components) else { return "" }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return FormatterCache.monthNameFormatter(locale: .appLocale).string(from: date)
  }

  /// Find the best (highest earnings) shift in a collection
  /// Returns the first shift chronologically if multiple have the same max earnings
  func findBestShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
    guard !shifts.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    // Find max gross earnings
    let maxGross = shifts.map(\.grossPay).max() ?? 0  // swiftlint:disable:this explicit_type_interface
    guard maxGross > 0 else { return shifts.first }  // swiftlint:disable:this conditional_returns_on_newline

    // Get all shifts with max earnings, sorted chronologically
    let bestShifts =  // swiftlint:disable:this explicit_type_interface
      shifts
      .filter { $0.grossPay == maxGross }
      .sorted { $0.shiftDate < $1.shiftDate }

    return bestShifts.first
  }
}
