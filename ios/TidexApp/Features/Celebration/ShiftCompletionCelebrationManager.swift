import Foundation

@MainActor
final class ShiftCompletionCelebrationManager: ObservableObject {
  static let shared = ShiftCompletionCelebrationManager()

  @Published var shouldShowCelebration: Bool = false
  @Published var celebrationData: CelebrationData?

  private var pendingState: CelebrationState?
  private var checkTask: Task<Void, Never>?

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

    let shiftsSnapshot = shifts
    let monthSnapshot = month
    let userIdSnapshot = userId
    let displayValueSnapshot = displayValue
    let displayTaxEnabledSnapshot = displayTaxEnabled
    let currencySnapshot = currency
    let includeVirtualSnapshot = includeVirtual

    checkTask = Task.detached(priority: .utility) { [weak self] in
      let now = Date()
      let completedIds = CelebrationDetector.completedShiftIds(
        shifts: shiftsSnapshot,
        now: now,
        includeVirtual: includeVirtualSnapshot
      )
      let stateKey = CelebrationPersistence.stateKey(
        userId: userIdSnapshot, year: monthSnapshot.year, month: monthSnapshot.month)
      let previousState = CelebrationPersistence.loadState(forKey: stateKey)
      #if DEBUG
        let debugForce = CelebrationPersistence.consumeDebugForceFlag(
          userId: userIdSnapshot,
          year: monthSnapshot.year,
          month: monthSnapshot.month
        )
      #else
        let debugForce = false
      #endif

      let previousCompletedIds = Set(previousState?.completedShiftIds ?? [])
      let newlyCompleted = CelebrationDetector.newlyCompletedShifts(
        shifts: shiftsSnapshot,
        previousCompletedIds: previousCompletedIds,
        now: now,
        includeVirtual: includeVirtualSnapshot
      )

      let baselineState = CelebrationState(
        lastDisplayValue: displayValueSnapshot,
        completedShiftIds: completedIds.sorted(),
        displayTaxEnabled: displayTaxEnabledSnapshot
      )

      let eligibleShifts =
        includeVirtualSnapshot
        ? shiftsSnapshot
        : shiftsSnapshot.filter { !$0.isVirtual }

      let result: CelebrationResult
      if debugForce {
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

        if let featuredShift {
          let previousDisplayValue =
            previousState?.lastDisplayValue
            ?? max(0, displayValueSnapshot - 1000)
          let animateFrom: Double? =
            previousState?.displayTaxEnabled != displayTaxEnabledSnapshot
            ? displayValueSnapshot
            : nil

          let data = CelebrationData(
            previousDisplayValue: previousDisplayValue,
            newDisplayValue: displayValueSnapshot,
            featuredShift: featuredShift,
            completedShiftCount: completedShifts.count,
            currency: currencySnapshot,
            animateFrom: animateFrom
          )
          result = .show(data: data, state: baselineState)
        } else {
          result = .store(state: baselineState)
        }
      } else if previousState == nil {
        // Establish baseline on first run of the month.
        result = .store(state: baselineState)
      } else if newlyCompleted.isEmpty {
        // No new completed shifts; update baseline to current state.
        result = .store(state: baselineState)
      } else if let featuredShift = CelebrationDetector.selectHighestEarningShift(
        from: newlyCompleted)
      {
        var animateFrom: Double? = nil
        if previousState?.displayTaxEnabled != displayTaxEnabledSnapshot {
          // Avoid misleading count-up when tax basis changed.
          animateFrom = displayValueSnapshot
        }

        let data = CelebrationData(
          previousDisplayValue: previousState?.lastDisplayValue ?? displayValueSnapshot,
          newDisplayValue: displayValueSnapshot,
          featuredShift: featuredShift,
          completedShiftCount: newlyCompleted.count,
          currency: currencySnapshot,
          animateFrom: animateFrom
        )

        result = .show(data: data, state: baselineState)
      } else {
        result = .store(state: baselineState)
      }

      guard !Task.isCancelled else { return }

      await MainActor.run { [weak self] in
        guard let self else { return }
        if self.shouldShowCelebration { return }
        self.apply(result: result, stateKey: stateKey)
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

      let maxAttempts = 5
      let retryDelayNs: UInt64 = 300_000_000
      var data:
        (
          settings: UserSettings, rawShifts: [ShiftRow], snapshots: [WageSnapshot],
          recurring: [RecurringShiftRow], jobs: [Job]
        )?

      for attempt in 1...maxAttempts {
        if Task.isCancelled { break }
        data = await MainActor.run {
          () -> (
            settings: UserSettings, rawShifts: [ShiftRow], snapshots: [WageSnapshot],
            recurring: [RecurringShiftRow], jobs: [Job]
          )? in
          let settingsRepository = SettingsRepository.shared
          guard let settings = settingsRepository.getSettings(for: userIdSnapshot) else {
            return nil
          }

          let shiftsRepository = ShiftsRepository.shared
          let snapshotsRepository = SnapshotsRepository.shared
          let recurringShiftsRepository = RecurringShiftsRepository.shared
          let jobsRepository = JobsRepository.shared

          let startDate = Date.firstDayOfMonthDate(year: current.year, month: current.month)
          let endDate = Date.lastDayOfMonthDate(year: current.year, month: current.month)

          let rawShifts = shiftsRepository.getShifts(
            for: userIdSnapshot,
            startDate: startDate,
            endDate: endDate
          )
          let snapshots = snapshotsRepository.getSnapshots(for: userIdSnapshot)
          let recurring = recurringShiftsRepository.getRecurringShifts(for: userIdSnapshot)
          let jobs = jobsRepository.getNonDeletedJobs(for: userIdSnapshot)

          return (settings, rawShifts, snapshots, recurring, jobs)
        }

        if data != nil {
          break
        }

        if attempt < maxAttempts {
          try? await Task.sleep(nanoseconds: retryDelayNs)
        }
      }

      guard let data else { return }

      let computedShifts = PayrollEngine.computeShiftsForMonth(
        .init(
          year: current.year,
          month: current.month,
          shifts: data.rawShifts,
          recurring: data.recurring,
          snapshots: data.snapshots,
          settings: data.settings,
          jobs: data.jobs
        )
      )

      let totals = PayrollEngine.summarizeShiftTotals(
        shifts: computedShifts,
        halfTaxMonth: data.settings.half_tax_month,
        earningsMonth: current.month,
        now: Date()
      )

      let displayTaxEnabled = computedShifts.first?.taxEnabled ?? false
      let displayValue = displayTaxEnabled ? totals.completedNet : totals.completedGross
      let currency = data.settings.currency ?? "kr"

      guard !Task.isCancelled else { return }

      await MainActor.run { [weak self] in
        guard let self else { return }
        self.checkForCelebration(
          userId: userIdSnapshot,
          month: current,
          shifts: computedShifts,
          displayValue: displayValue,
          displayTaxEnabled: displayTaxEnabled,
          currency: currency,
          includeVirtual: true
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
