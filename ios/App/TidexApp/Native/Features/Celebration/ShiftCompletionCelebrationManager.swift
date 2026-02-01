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
        dashboardData: DashboardData,
        settings: UserSettings
    ) {
        guard !userId.isEmpty else { return }
        guard !shouldShowCelebration else { return }

        checkTask?.cancel()

        let shiftsSnapshot = shifts
        let dashboardSnapshot = dashboardData
        let monthSnapshot = month
        let userIdSnapshot = userId
        let currencySnapshot = settings.currency ?? dashboardData.currency

        checkTask = Task.detached(priority: .utility) { [weak self] in
            let now = Date()
            let completedIds = CelebrationDetector.completedShiftIds(
                shifts: shiftsSnapshot,
                now: now
            )
            let display = CelebrationDetector.displayValue(dashboardData: dashboardSnapshot)
            let stateKey = CelebrationPersistence.stateKey(userId: userIdSnapshot, year: monthSnapshot.year, month: monthSnapshot.month)
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
                now: now
            )

            let baselineState = CelebrationState(
                lastDisplayValue: display.value,
                completedShiftIds: completedIds.sorted(),
                displayTaxEnabled: display.taxEnabled
            )

            let result: CelebrationResult
            if debugForce {
                let completedShifts = shiftsSnapshot.filter { shift in
                    if shift.isVirtual { return false }
                    return Date.hasShiftEnded(
                        shiftDate: shift.shiftDate,
                        startTime: shift.startTime,
                        endTime: shift.endTime,
                        referenceDate: now
                    )
                }
                let featuredShift = CelebrationDetector.selectHighestEarningShift(from: completedShifts)
                    ?? shiftsSnapshot.first(where: { !$0.isVirtual })

                if let featuredShift {
                    let previousDisplayValue = previousState?.lastDisplayValue
                        ?? max(0, display.value - 1000)
                    let animateFrom: Double? = previousState?.displayTaxEnabled != display.taxEnabled
                        ? display.value
                        : nil

                    let data = CelebrationData(
                        previousDisplayValue: previousDisplayValue,
                        newDisplayValue: display.value,
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
            } else if let featuredShift = CelebrationDetector.selectHighestEarningShift(from: newlyCompleted) {
                var animateFrom: Double? = nil
                if previousState?.displayTaxEnabled != display.taxEnabled {
                    // Avoid misleading count-up when tax basis changed.
                    animateFrom = display.value
                }

                let data = CelebrationData(
                    previousDisplayValue: previousState?.lastDisplayValue ?? display.value,
                    newDisplayValue: display.value,
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
                if self.shouldShowCelebration {
                    return
                }
                self.apply(result: result, stateKey: stateKey)
            }
        }
    }

    func dismissCelebration(userId: String, month: (year: Int, month: Int)) {
        guard !userId.isEmpty else { return }
        let stateKey = CelebrationPersistence.stateKey(userId: userId, year: month.year, month: month.month)

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
