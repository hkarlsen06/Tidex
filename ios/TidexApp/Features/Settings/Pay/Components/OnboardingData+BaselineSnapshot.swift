import Foundation

extension OnboardingData {
  /// The wage snapshot a job starts with, built from the pay setup answers.
  var baselineSnapshotInput: JobBaselineSnapshotInput {
    JobBaselineSnapshotInput(
      hourlyWage: resolvedHourlyWage,
      wageLevel: resolvedWageLevel,
      tariffTypeId: resolvedTariffTypeId,
      supplements: resolvedSupplements,
      overtime: resolvedOvertime,
      taxEnabled: taxEnabled,
      taxPercentage: taxEnabled ? taxPercentage : nil,
      breakEnabled: breakEnabled,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30
    )
  }
}
