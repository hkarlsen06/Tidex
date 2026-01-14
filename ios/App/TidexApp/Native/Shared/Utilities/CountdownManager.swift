import Foundation
import Combine

/// Observable manager for countdown updates
/// Provides live-updating countdown text for shifts and payroll
@MainActor
final class CountdownManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var shiftCountdownText: String?
    @Published private(set) var isShiftActive: Bool = false
    @Published private(set) var payrollCountdownText: String?
    @Published private(set) var isPayrollToday: Bool = false
    @Published private(set) var isPayrollPast: Bool = false

    // MARK: - Private State

    private var timer: Timer?
    private var shiftDate: String?
    private var startTime: String?
    private var endTime: String?
    private var payrollDate: Date?
    private var isNorwegian: Bool = false

    // MARK: - Public Methods

    /// Configure the countdown manager with shift and payroll data
    func configure(
        shiftDate: String?,
        startTime: String?,
        endTime: String?,
        payrollDate: Date?,
        isNorwegian: Bool
    ) {
        self.shiftDate = shiftDate
        self.startTime = startTime
        self.endTime = endTime
        self.payrollDate = payrollDate
        self.isNorwegian = isNorwegian

        // Update immediately
        updateCountdowns()

        // Start timer for live updates
        startTimer()
    }

    /// Stop the countdown timer
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private Methods

    private func startTimer() {
        timer?.invalidate()

        // Update every second for responsive countdown
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdowns()
            }
        }
    }

    private func updateCountdowns() {
        // Update shift countdown
        if let shiftDate = shiftDate,
           let startTime = startTime,
           let endTime = endTime {
            let (text, isActive) = CountdownFormatter.formatShiftCountdown(
                shiftDate: shiftDate,
                startTime: startTime,
                endTime: endTime,
                isNorwegian: isNorwegian
            )
            self.shiftCountdownText = text
            self.isShiftActive = isActive
        } else {
            self.shiftCountdownText = nil
            self.isShiftActive = false
        }

        // Update payroll countdown
        if let payrollDate = payrollDate {
            let (text, isPast, isToday) = CountdownFormatter.formatPayrollCountdown(
                payrollDate: payrollDate,
                isNorwegian: isNorwegian
            )
            self.payrollCountdownText = text
            self.isPayrollPast = isPast
            self.isPayrollToday = isToday
        } else {
            self.payrollCountdownText = nil
            self.isPayrollPast = false
            self.isPayrollToday = false
        }
    }

    deinit {
        timer?.invalidate()
    }
}
