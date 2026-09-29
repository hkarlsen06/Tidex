import Foundation

// MARK: - Editor Input Model

/// Input data for creating/updating a wage snapshot
struct WageSnapshotEditorInput {
  var fromDate: Date?
  var hourlyWage: Double
  var wageLevel: Int?
  var supplements: SupplementRulesSnapshot
  var overtime: OvertimeConfig
  var taxEnabled: Bool
  var taxPercentage: Double
  var breakEnabled: Bool
  var breakMethod: BreakMethod
  var breakThresholdHours: Double
  var breakDeductionMinutes: Int
  /// Tariff type ID when using tariff rates (e.g., "hk_retail")
  var tariffTypeId: String?

  init(effectiveDate: Date, snapshots: [WageSnapshot]) {
    self.init(
      prefillFrom: SnapshotsService.snapshotForDate(
        effectiveDate.toISODateString(), from: snapshots
      ))
    fromDate = effectiveDate
  }

  /// When a new change moves to another period, carry forward that period's
  /// settings while retaining the fields the user has deliberately changed.
  func rebasingUneditedSettings(from previous: WageSnapshot, onto next: WageSnapshot) -> Self {
    let original = Self(from: previous)
    let replacement = Self(from: next)
    var result = self

    if hourlyWage == original.hourlyWage, wageLevel == original.wageLevel,
      tariffTypeId == original.tariffTypeId
    {
      result.hourlyWage = replacement.hourlyWage
      result.wageLevel = replacement.wageLevel
      result.tariffTypeId = replacement.tariffTypeId
    }
    if supplements == original.supplements {
      result.supplements = replacement.supplements
    }
    if overtime == original.overtime {
      result.overtime = replacement.overtime
    }
    if taxEnabled == original.taxEnabled, taxPercentage == original.taxPercentage {
      result.taxEnabled = replacement.taxEnabled
      result.taxPercentage = replacement.taxPercentage
    }
    if breakEnabled == original.breakEnabled, breakMethod == original.breakMethod,
      breakThresholdHours == original.breakThresholdHours,
      breakDeductionMinutes == original.breakDeductionMinutes
    {
      result.breakEnabled = replacement.breakEnabled
      result.breakMethod = replacement.breakMethod
      result.breakThresholdHours = replacement.breakThresholdHours
      result.breakDeductionMinutes = replacement.breakDeductionMinutes
    }
    return result
  }

  /// Create input from an existing snapshot
  init(from snapshot: WageSnapshot) {
    if let fromDateString = snapshot.from_date {
      self.fromDate = Date.fromISODateString(fromDateString)
    } else {
      self.fromDate = nil
    }
    self.hourlyWage = snapshot.hourly_wage
    self.wageLevel = snapshot.wage_level
    self.supplements = snapshot.supplements
    self.overtime = snapshot.overtime
    self.taxEnabled = snapshot.effectiveTaxEnabled
    self.taxPercentage = snapshot.effectiveTaxPercentage
    self.breakEnabled = snapshot.effectiveBreakEnabled && snapshot.breakMethod != .none
    self.breakMethod = snapshot.breakMethod
    self.breakThresholdHours = snapshot.effectiveBreakThresholdHours
    self.breakDeductionMinutes = snapshot.effectiveBreakDeductionMinutes
    self.tariffTypeId = snapshot.tariff_type_id
  }

  /// Create default input for new snapshot
  init(prefillFrom snapshot: WageSnapshot? = nil) {
    self.fromDate = Date()

    if let snapshot {
      self.hourlyWage = snapshot.hourly_wage
      self.wageLevel = snapshot.wage_level
      self.supplements = snapshot.supplements
      self.overtime = snapshot.overtime
      self.taxEnabled = snapshot.effectiveTaxEnabled
      self.taxPercentage = snapshot.effectiveTaxPercentage
      self.breakEnabled = snapshot.effectiveBreakEnabled && snapshot.breakMethod != .none
      self.breakMethod = snapshot.breakMethod
      self.breakThresholdHours = snapshot.effectiveBreakThresholdHours
      self.breakDeductionMinutes = snapshot.effectiveBreakDeductionMinutes
      self.tariffTypeId = snapshot.tariff_type_id
    } else {
      self.hourlyWage = 184.54
      self.wageLevel = 1
      self.supplements = SupplementRulesSnapshot(rules: PayrollCalculator.presetSupplementRules)
      self.overtime = .disabled
      self.taxEnabled = false
      self.taxPercentage = 0
      self.breakEnabled = true
      self.breakMethod = .proportional
      self.breakThresholdHours = 5.5
      self.breakDeductionMinutes = 30
      self.tariffTypeId = nil
    }
  }
}

// MARK: - WageSnapshotEditorInput Extension

extension WageSnapshotEditorInput {
  /// Create input with explicit values (for editor sheet)
  init(
    fromDate: Date?,
    hourlyWage: Double,
    wageLevel: Int?,
    supplements: SupplementRulesSnapshot,
    overtime: OvertimeConfig = .disabled,
    taxEnabled: Bool,
    taxPercentage: Double,
    breakEnabled: Bool,
    breakMethod: BreakMethod,
    breakThresholdHours: Double,
    breakDeductionMinutes: Int,
    tariffTypeId: String? = nil
  ) {
    self.fromDate = fromDate
    self.hourlyWage = hourlyWage
    self.wageLevel = wageLevel
    self.supplements = supplements
    self.overtime = overtime
    self.taxEnabled = taxEnabled
    self.taxPercentage = taxPercentage
    self.breakEnabled = breakEnabled
    self.breakMethod = breakMethod
    self.breakThresholdHours = breakThresholdHours
    self.breakDeductionMinutes = breakDeductionMinutes
    self.tariffTypeId = tariffTypeId
  }
}
