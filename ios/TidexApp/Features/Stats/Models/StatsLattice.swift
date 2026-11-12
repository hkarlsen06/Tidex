import Foundation

/// The Stats screen for one month, padded to slots that never change in number: 31 days,
/// 6 week rows of 7 days and 12 months. Views fill the slots and never branch on whether data
/// exists, so a month change swaps values in place and moves nothing.
///
/// Every amount is in the hero's basis: after tax when `hero.isAfterTax` is true, before tax
/// otherwise. Views never convert.
struct StatsLattice: Equatable {
  static let daySlots: Int = 31
  static let weekRows: Int = 6
  static let monthSlots: Int = 12

  enum Phase: Equatable {
    case past
    case current(today: Int)
    case future
  }

  enum Qualifier: Equatable {
    /// No shifts in the period. `isAhead` is true when the period has not started yet, so
    /// shifts are only not planned yet.
    case noShifts(isAhead: Bool)
    /// Pay before tax, shown beside an amount after tax.
    case taxed(gross: Double)
    case untaxed
  }

  enum Change: Equatable {
    /// Against the whole previous month or year.
    case percent(Double)
    /// The running year against the previous year on the same date.
    case percentSameTime(Double)
    case noPreviousPay
  }

  /// What the hero sums, which decides its copy.
  enum Period: Equatable {
    /// `showsYear` is true outside the current year, so the month name carries the year.
    case month(FocusMonth, showsYear: Bool)
    case year(Int)
  }

  /// Pay this month in currencies other than the one the screen shows.
  enum OtherCurrencies: Equatable {
    case absent
    case one(amount: Double, currency: String)
    case several(count: Int)
  }

  struct Hero: Equatable {
    let period: Period
    let isAfterTax: Bool
    let amount: Double
    /// Pay for the shifts already worked, in the hero's basis. Set only for the running month
    /// when it also has shifts that are still scheduled, so `amount` is more than what is earned.
    let earnedSoFar: Double?
    let qualifier: Qualifier
    let change: Change
    let otherCurrencies: OtherCurrencies
    let breakdown: [JobCurrencyAggregateEntry]
  }

  struct Metrics: Equatable {
    let hours: Double
    let shifts: Int
    /// Pay per paid hour in the primary currency and the hero's basis, nil without paid hours.
    let perHour: Double?
  }

  struct PaceSeries: Equatable, Identifiable {
    enum Role: Equatable {
      case focus
      case previous
    }

    /// The month's `monthIndex`, so a month keeps its line when it changes role.
    let id: Int
    let role: Role
    /// Cumulative pay for each of the 31 day slots. Slots after the last day repeat its value.
    let values: [Double]
    let dayCount: Int
    /// Solid through this day and fainter after it, where shifts are only scheduled.
    let solidThrough: Int
  }

  enum PaceReference: Equatable {
    /// The current month reads today and marks it on the plot.
    case today(Int)
    /// Other months read their last day.
    case monthEnd(Int)

    var day: Int {
      switch self {
      case .today(let day), .monthEnd(let day): day
      }
    }
  }

  enum PaceHeadline: Equatable {
    /// The month is drawn beside the month before.
    case versus(previous: FocusMonth)
    /// The month before has no pay, so the month is drawn alone.
    case alone
  }

  struct Pace: Equatable {
    let month: FocusMonth
    let previousMonth: FocusMonth
    let showsYear: Bool
    let focus: PaceSeries
    let previous: PaceSeries
    let yMax: Double
    let dayCount: Int
    let reference: PaceReference
    let headline: PaceHeadline
  }

  enum DayMark: Equatable {
    case empty
    /// The payload is the day's pay as a share of the month's biggest day, from 0 to 1.
    case worked(Double)
    case scheduled(Double)
  }

  enum DayCell: Equatable {
    case outside
    case day(DayStats, mark: DayMark, isToday: Bool)
  }

  struct WeekRow: Equatable, Identifiable {
    let id: Int
    let isoWeek: Int
    let cells: [DayCell]
    /// Pay on the row's days inside the focus month, so the rows add up to the month.
    let total: Double
    let shiftCount: Int
    let isCurrent: Bool
    let isBest: Bool
    /// The row has shifts and all of them are still scheduled.
    let isPlannedOnly: Bool
  }

  enum WeeksHeadline: Equatable {
    case noShifts(FocusMonth)
    case noPay(FocusMonth)
    case soFar(amount: Double, week: Int)
    /// Only when at least two weeks have pay and one is strictly highest.
    case best(week: Int, amount: Double)
    /// Same rule as `best`, for a month that has not started.
    case busiestAhead(week: Int)
    /// No single week stands out, so the sentence gives the month's pay.
    case total(amount: Double)
  }

  /// `bestDay` and `biggestDay` only when one day is strictly highest. Otherwise `hint`.
  enum DayReadout: Equatable {
    case day(DayStats)
    case bestDay(DayStats)
    case biggestDay(DayStats)
    case hint
  }

  struct Weeks: Equatable {
    let month: FocusMonth
    let showsYear: Bool
    let rows: [WeekRow]
    let headline: WeeksHeadline
    let readout: DayReadout
  }

  enum Employment: Equatable {
    case noShifts
    /// A completed month with shifts, part of the average.
    case counted(Double)
    /// The running month or a later one, left out of the average.
    case running(Double)
  }

  struct MonthSlot: Equatable, Identifiable {
    let id: Int
    let earnings: Double
    /// After the real current month, so its pay is only scheduled.
    let isAhead: Bool
  }

  enum EmploymentAverage: Equatable {
    case noCompletedMonths
    case average(Double, range: String?)
  }

  /// Employment for each month of a year, drawn on both the month and the year page.
  struct EmploymentYear: Equatable {
    let year: Int
    /// One entry per month slot.
    let months: [Employment]
    let average: EmploymentAverage
    let fullTimeHoursPerWeek: Double

    /// False for a year with no shifts, which draws only its baseline.
    var hasShifts: Bool { months.contains { $0 != .noShifts } }
  }

  /// Where the focus month's pay sits among the months of its year.
  enum Standing: Equatable {
    case noPayInYear
    case noPayInMonth
    /// The month has not started and has no pay planned.
    case nothingPlanned
    /// The highest pay of the year so far, alone or tied.
    case best
    /// Pay minus the year's average paid month. Positive is above.
    case againstAverage(Double)
  }

  struct Year: Equatable {
    let year: Int
    let months: [MonthSlot]
    let yMax: Double
    let total: Double
    let perPaidMonth: Double?
    let standing: Standing
    let focus: Int
    /// The real current month when the focus year is this year.
    let currentMonth: Int?
    let employment: EmploymentYear
  }

  let month: FocusMonth
  let phase: Phase
  let hero: Hero
  let metrics: Metrics
  let pace: Pace
  let weeks: Weeks
  let year: Year

  /// Rounds up to 1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a power of ten, so scale labels stay short.
  static func niceCeiling(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let power = pow(10, floor(log10(value)))
    let steps: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
    return (steps.first { $0 * power >= value } ?? 10) * power
  }
}

extension StatsLattice.Employment {
  /// The month's employment percent, 0 without shifts.
  var value: Double {
    switch self {
    case .noShifts: 0
    case .counted(let value), .running(let value): value
    }
  }

  var percent: Double? {
    self == .noShifts ? nil : value
  }
}

extension StatsLattice.DayCell {
  var dayStats: DayStats? {
    if case .day(let stats, _, _) = self { stats } else { nil }
  }

  var isToday: Bool {
    if case .day(_, _, let isToday) = self { isToday } else { false }
  }
}

extension FocusMonth {
  /// `year * 12 + month`, which orders months and gives each one a stable identity.
  var monthIndex: Int { year * 12 + month }

  var previous: FocusMonth {
    month == 1 ? FocusMonth(year: year - 1, month: 12) : FocusMonth(year: year, month: month - 1)
  }
}
