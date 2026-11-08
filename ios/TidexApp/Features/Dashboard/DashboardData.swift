import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

/// Computed dashboard data ready for display
struct DashboardData: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  // Month Context
  let displayedYear: Int  // swiftlint:disable:this explicit_acl
  let displayedMonth: Int  // swiftlint:disable:this explicit_acl

  // Payroll Card (Previous Month)
  let payrollDate: Date  // swiftlint:disable:this explicit_acl
  let payrollHasPassed: Bool  // true = previous payout, false = next payout // swiftlint:disable:this explicit_acl
  let previousMonthGross: Double  // swiftlint:disable:this explicit_acl
  let previousMonthNet: Double?  // nil if tax not enabled // swiftlint:disable:this explicit_acl
  let previousMonthTax: Double?  // swiftlint:disable:this explicit_acl
  let previousMonthTaxEnabled: Bool  // swiftlint:disable:this explicit_acl
  let previousMonthHasPayrollAdjustments: Bool  // swiftlint:disable:this explicit_acl

  // Total Card (Current Month)
  let currentMonthGross: Double  // All shifts (projected total) // swiftlint:disable:this explicit_acl
  let currentMonthNet: Double?  // All shifts net (projected) // swiftlint:disable:this explicit_acl
  let currentMonthCompletedGross: Double  // Only completed shifts (earned to date)  // swiftlint:disable:this explicit_acl line_length
  let currentMonthCompletedNet: Double?  // Only completed shifts net // swiftlint:disable:this explicit_acl
  let currentMonthShiftCount: Int  // Total shift count // swiftlint:disable:this explicit_acl
  let currentMonthCompletedCount: Int  // Completed shifts count // swiftlint:disable:this explicit_acl
  let currentMonthPlannedCount: Int  // Future shifts // swiftlint:disable:this explicit_acl
  let percentageChangeVsPrevious: Double?  // swiftlint:disable:this explicit_acl
  let currentMonthTaxEnabled: Bool  // swiftlint:disable:this explicit_acl

  // Featured Home Card
  // For current month: next upcoming shift or calendar event
  // For other months: best shift (highest earnings) in that month
  let featuredItem: DashboardFeaturedItem?  // swiftlint:disable:this explicit_acl
  let featuredShift: ShiftWithComputations?  // swiftlint:disable:this explicit_acl
  let isFeaturedItemToday: Bool  // swiftlint:disable:this explicit_acl
  let featuredShiftIsBestShift: Bool  // true = showing best shift, false = showing next shift  // swiftlint:disable:this explicit_acl line_length

  // Metadata
  let currentMonthName: String  // swiftlint:disable:this explicit_acl
  let previousMonthName: String  // swiftlint:disable:this explicit_acl

  // User Settings
  let currency: String  // User's selected currency (e.g., "kr", "$", "€") // swiftlint:disable:this explicit_acl
  let currentMonthCurrencyAggregate: JobCurrencyAggregateResolution  // swiftlint:disable:this explicit_acl

  /// Whether there are future shifts (main display should be projected total)
  var hasFutureShifts: Bool {  // swiftlint:disable:this explicit_acl
    currentMonthPlannedCount > 0
  }

  /// Whether this dashboard payload represents the real current month.
  var isViewingCurrentMonth: Bool {  // swiftlint:disable:this explicit_acl
    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    return displayedYear == current.year && displayedMonth == current.month
  }
}