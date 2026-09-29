import Foundation
import Observation

@MainActor
@Observable
final class ShiftCompletionCelebrationManager {
  static let shared = ShiftCompletionCelebrationManager()

  var shouldShowCelebration: Bool = false
  var celebrationData: CelebrationData?

  @ObservationIgnored private var pendingState: CelebrationState?
  @ObservationIgnored private var checkTask: Task<Void, Never>?

  private init() {}

  func checkForCelebration(
    userId: String,
    month: (year: Int, month: Int),
    shifts: [ShiftWithComputations],
    displayValue: Double,
    displayTaxEnabled: Bool,
    currency: String,
    includeVirtual: Bool = true
  ) {
    guard !userId.isEmpty else { return }
    guard !shouldShowCelebration else { return }

    checkTask?.cancel()

    let input = CelebrationInput(
      userId: userId,
      month: month,
      shifts: shifts,
      displayValue: displayValue,
      displayTaxEnabled: displayTaxEnabled,
      currency: currency,
      includeVirtual: includeVirtual
    )

    checkTask = Task.detached(priority: .utility) { [weak self] in
      let stateKey = input.stateKey
      let result = CelebrationEvaluator.evaluate(input)

      guard !Task.isCancelled else { return }

      await MainActor.run { [weak self] in
        guard let self else { return }
        // swiftlint:disable:next conditional_returns_on_newline
        if shouldShowCelebration { return }
        apply(result: result, stateKey: stateKey)
      }
    }
  }

  func checkForCelebrationFromLocal(userId: String) {
    guard !userId.isEmpty else { return }
    guard !shouldShowCelebration else { return }

    checkTask?.cancel()

    let userIdSnapshot = userId

    checkTask = Task.detached(priority: .utility) { [weak self] in
      let current = Date.currentYearMonth()

      guard
        let data = await LocalCelebrationData.loadWithRetry(userId: userIdSnapshot, month: current)
      else { return }

      let input = data.celebrationInput(userId: userIdSnapshot, month: current)

      guard !Task.isCancelled else { return }

      await MainActor.run { [weak self] in
        guard let self else { return }
        checkForCelebration(
          userId: input.userId,
          month: input.month,
          shifts: input.shifts,
          displayValue: input.displayValue,
          displayTaxEnabled: input.displayTaxEnabled,
          currency: input.currency,
          includeVirtual: input.includeVirtual
        )
      }
    }
  }

  func dismissCelebration(userId: String, month: (year: Int, month: Int)) {
    guard !userId.isEmpty else { return }
    let stateKey = CelebrationPersistence.stateKey(
      userId: userId, year: month.year, month: month.month)

    if let pendingState {
      CelebrationPersistence.saveState(pendingState, forKey: stateKey)
    }

    pendingState = nil
    celebrationData = nil
    shouldShowCelebration = false
  }

  #if DEBUG
    func requestDebugCelebration(userId: String, month: (year: Int, month: Int)) {
      guard !userId.isEmpty else { return }
      CelebrationPersistence.setDebugForceFlag(
        userId: userId,
        year: month.year,
        month: month.month
      )
    }
  #endif

  private func apply(result: CelebrationResult, stateKey: String) {
    switch result {
    case .show(let data, let state):
      #if DEBUG
        // App Store captures happen whenever the fixture month overlaps today.
        if AppStoreScreenshotFixture.isActive { return }
      #endif
      pendingState = state
      celebrationData = data
      shouldShowCelebration = true

    case .store(let state):
      CelebrationPersistence.saveState(state, forKey: stateKey)
      pendingState = nil
      celebrationData = nil
      shouldShowCelebration = false

    case .none:
      break
    }
  }
}

struct CelebrationData: Equatable {
  let previousDisplayValue: Double
  let newDisplayValue: Double
  let featuredShift: ShiftWithComputations
  let completedShiftCount: Int
  let currency: String
  let animateFrom: Double?
}

struct CelebrationState: Codable, Equatable {
  let lastDisplayValue: Double
  let completedShiftIds: [String]
  let displayTaxEnabled: Bool
}

private enum CelebrationResult {
  case show(data: CelebrationData, state: CelebrationState)
  case store(state: CelebrationState)
  case none
}

private struct CelebrationInput {
  let userId: String
  let month: (year: Int, month: Int)
  let shifts: [ShiftWithComputations]
  let displayValue: Double
  let displayTaxEnabled: Bool
  let currency: String
  let includeVirtual: Bool

  var stateKey: String {
    CelebrationPersistence.stateKey(userId: userId, year: month.year, month: month.month)
  }

  func celebrationData(
    featuredShift: ShiftWithComputations,
    completedShiftCount: Int,
    previousDisplayValue: Double,
    taxBasisChanged: Bool
  ) -> CelebrationData {
    CelebrationData(
      previousDisplayValue: previousDisplayValue,
      newDisplayValue: displayValue,
      featuredShift: featuredShift,
      completedShiftCount: completedShiftCount,
      currency: currency,
      animateFrom: taxBasisChanged ? displayValue : nil
    )
  }
}

private enum CelebrationEvaluator {
  static func evaluate(_ input: CelebrationInput) -> CelebrationResult {
    let now = Date()
    let completedIds = CelebrationDetector.completedShiftIds(
      shifts: input.shifts,
      now: now,
      includeVirtual: input.includeVirtual
    )
    let previousState = CelebrationPersistence.loadState(forKey: input.stateKey)
    #if DEBUG
      let debugForce = CelebrationPersistence.consumeDebugForceFlag(
        userId: input.userId,
        year: input.month.year,
        month: input.month.month
      )
    #else
      let debugForce = false
    #endif

    let baselineState = CelebrationState(
      lastDisplayValue: input.displayValue,
      completedShiftIds: completedIds.sorted(),
      displayTaxEnabled: input.displayTaxEnabled
    )

    if debugForce {
      return debugResult(
        input, previousState: previousState, baselineState: baselineState, now: now)
    }
    return regularResult(
      input, previousState: previousState, baselineState: baselineState, now: now)
  }

  private static func regularResult(
    _ input: CelebrationInput,
    previousState: CelebrationState?,
    baselineState: CelebrationState,
    now: Date
  ) -> CelebrationResult {
    let newlyCompleted = CelebrationDetector.newlyCompletedShifts(
      shifts: input.shifts,
      previousCompletedIds: Set(previousState?.completedShiftIds ?? []),
      now: now,
      includeVirtual: input.includeVirtual
    )

    // No previous state means first run of the month, so establish the baseline.
    // No new completed shifts means only the baseline needs updating.
    guard let previousState, !newlyCompleted.isEmpty,
      let featuredShift = CelebrationDetector.selectHighestEarningShift(from: newlyCompleted)
    else {
      return .store(state: baselineState)
    }

    // Avoid a misleading count-up when the tax basis changed.
    let taxBasisChanged = previousState.displayTaxEnabled != input.displayTaxEnabled
    let data = input.celebrationData(
      featuredShift: featuredShift,
      completedShiftCount: newlyCompleted.count,
      previousDisplayValue: previousState.lastDisplayValue,
      taxBasisChanged: taxBasisChanged
    )
    return .show(data: data, state: baselineState)
  }

  private static func debugResult(
    _ input: CelebrationInput,
    previousState: CelebrationState?,
    baselineState: CelebrationState,
    now: Date
  ) -> CelebrationResult {
    let eligibleShifts =
      input.includeVirtual
      ? input.shifts
      : input.shifts.filter { !$0.isVirtual }

    let completedShifts = eligibleShifts.filter { shift in
      Date.hasShiftEnded(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        referenceDate: now
      )
    }
    let featuredShift =
      CelebrationDetector.selectHighestEarningShift(from: completedShifts)
      ?? eligibleShifts.first

    guard let featuredShift else { return .store(state: baselineState) }

    let data = input.celebrationData(
      featuredShift: featuredShift,
      completedShiftCount: completedShifts.count,
      // swiftlint:disable:next no_magic_numbers
      previousDisplayValue: previousState?.lastDisplayValue ?? max(0, input.displayValue - 1_000),
      taxBasisChanged: previousState?.displayTaxEnabled != input.displayTaxEnabled
    )
    return .show(data: data, state: baselineState)
  }
}

private struct LocalCelebrationData {
  let settings: UserSettings
  let rawShifts: [ShiftRow]
  let snapshots: [WageSnapshot]
  let recurring: [RecurringShiftRow]
  let jobs: [Job]

  @MainActor
  static func load(userId: String, month: (year: Int, month: Int)) -> LocalCelebrationData? {
    guard let settings = SettingsRepository.shared.getSettings(for: userId) else {
      return nil
    }

    let startDate = Date.firstDayOfMonthDate(year: month.year, month: month.month)
    let endDate = Date.lastDayOfMonthDate(year: month.year, month: month.month)

    return LocalCelebrationData(
      settings: settings,
      rawShifts: ShiftsRepository.shared.getShifts(
        for: userId,
        startDate: startDate,
        endDate: endDate
      ),
      snapshots: SnapshotsRepository.shared.getSnapshots(for: userId),
      recurring: RecurringShiftsRepository.shared.getRecurringShifts(for: userId),
      jobs: JobsRepository.shared.getNonDeletedJobs(for: userId)
    )
  }

  static func loadWithRetry(
    userId: String, month: (year: Int, month: Int)
  ) async -> LocalCelebrationData? {
    let maxAttempts = 5
    let retryDelayNs: UInt64 = 300_000_000
    var data: LocalCelebrationData?

    for attempt in 1...maxAttempts {
      if Task.isCancelled { break }
      data = await MainActor.run { load(userId: userId, month: month) }

      if data != nil {
        break
      }

      if attempt < maxAttempts {
        try? await Task.sleep(nanoseconds: retryDelayNs)
      }
    }
    return data
  }

  func celebrationInput(userId: String, month: (year: Int, month: Int)) -> CelebrationInput {
    let computedShifts = PayrollEngine.computeShiftsForMonth(
      .init(
        year: month.year,
        month: month.month,
        shifts: rawShifts,
        recurring: recurring,
        snapshots: snapshots,
        settings: settings,
        jobs: jobs
      )
    )

    let totals = PayrollEngine.summarizeShiftTotals(
      shifts: computedShifts,
      halfTaxMonth: settings.half_tax_month,
      earningsMonth: month.month,
      now: Date()
    )

    let displayTaxEnabled = computedShifts.first?.taxEnabled ?? false
    return CelebrationInput(
      userId: userId,
      month: month,
      shifts: computedShifts,
      displayValue: displayTaxEnabled ? totals.completedNet : totals.completedGross,
      displayTaxEnabled: displayTaxEnabled,
      currency: settings.currency ?? "kr",
      includeVirtual: true
    )
  }
}

private enum CelebrationPersistence {
  static func stateKey(userId: String, year: Int, month: Int) -> String {
    "celebration_state.\(userId).\(year).\(month)"
  }

  static func loadState(forKey key: String) -> CelebrationState? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(CelebrationState.self, from: data)
  }

  static func saveState(_ state: CelebrationState, forKey key: String) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  #if DEBUG
    static func debugForceKey(userId: String, year: Int, month: Int) -> String {
      "celebration_debug.force.\(userId).\(year).\(month)"
    }

    static func setDebugForceFlag(userId: String, year: Int, month: Int) {
      let key = debugForceKey(userId: userId, year: year, month: month)
      UserDefaults.standard.set(true, forKey: key)
    }

    static func consumeDebugForceFlag(userId: String, year: Int, month: Int) -> Bool {
      let key = debugForceKey(userId: userId, year: year, month: month)
      let value = UserDefaults.standard.bool(forKey: key)
      if value {
        UserDefaults.standard.removeObject(forKey: key)
      }
      return value
    }
  #endif
}
