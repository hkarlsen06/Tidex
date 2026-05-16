import Foundation

enum PayrollAdjustmentCategory: String, Codable, CaseIterable {
  case retroPay = "retro_pay"
  case bonus
  case correction
  case other
}

enum PayrollAdjustmentTaxTreatment: String, Codable, CaseIterable {
  case grossTaxable = "gross_taxable"
  case netManual = "net_manual"
  case excludedFromTaxEstimate = "excluded_from_tax_estimate"
}

struct PayrollAdjustment: Codable, Identifiable, Equatable {
  let id: String
  let user_id: String
  let job_id: String?
  let amount: Double
  let currency: String
  let category: PayrollAdjustmentCategory
  let tax_treatment: PayrollAdjustmentTaxTreatment
  let description: String
  let note: String?
  let curated_note: String?
  let curated_link: String?
  let earned_from_date: String?
  let earned_to_date: String?
  let payout_date: String
  let created_at: String?
  let updated_at: String?
  let revision: Int64?
  let deleted_at: String?

  var isDeleted: Bool {
    deleted_at != nil
  }
}

struct PayrollAdjustmentTotals: Equatable {
  let gross: Double
  let net: Double
  let taxEnabled: Bool

  static var zero: PayrollAdjustmentTotals {
    PayrollAdjustmentTotals(gross: 0, net: 0, taxEnabled: false)
  }
}
