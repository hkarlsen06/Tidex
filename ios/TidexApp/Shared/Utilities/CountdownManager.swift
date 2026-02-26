import Combine
import Foundation

/// Observable manager for countdown updates
/// Provides live-updating countdown text for shifts and payroll
@MainActor
final class CountdownManager: ObservableObject {

  // MARK: - Published State

  @Published private(set) var shiftCountdownText: String?
  @Published private(set) var isShiftActive: Bool = false
  @Published private(set) var shiftProgress: Double = 0  // 0-100, only meaningful when isShiftActive
  @Published private(set) var finalShiftCountdownSeconds: Int?
  @Published private(set) var payrollCountdownText: String?
  @Published private(set) var isPayrollToday: Bool = false
  @Published private(set) var isPayrollPast: Bool = false

  // MARK: - Private State

  private var timerCancellable: AnyCancellable?
  private var shiftDate: String?
  private var startTime: String?
  private var endTime: String?
  private var payrollDate: Date?

  // MARK: - Public Methods

  /// Configure the countdown manager with shift and payroll data
  func configure(
    shiftDate: String?,
    startTime: String?,
    endTime: String?,
    payrollDate: Date?
  ) {
    self.shiftDate = shiftDate
    self.startTime = startTime
    self.endTime = endTime
    self.payrollDate = payrollDate

    // Update immediately
    updateCountdowns()

    // Start timer for live updates
    startTimer()
  }

  /// Stop the countdown timer
  func stop() {
    timerCancellable?.cancel()
    timerCancellable = nil
  }

  // MARK: - Private Methods

  private func startTimer() {
    timerCancellable?.cancel()

    // Use common run loop mode so updates continue during gestures/scrolling.
    timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.updateCountdowns()
      }
  }

  private func updateCountdowns() {
    // Update shift countdown
    if let shiftDate = shiftDate,
      let startTime = startTime,
      let endTime = endTime
    {
      let (text, isActive, progress) = CountdownFormatter.formatShiftCountdown(
        shiftDate: shiftDate,
        startTime: startTime,
        endTime: endTime
      )
      self.shiftCountdownText = text
      self.isShiftActive = isActive
      self.shiftProgress = progress
      self.finalShiftCountdownSeconds = CountdownFormatter.finalCountdownSecondsForShift(
        shiftDate: shiftDate,
        startTime: startTime,
        endTime: endTime
      )
    } else {
      self.shiftCountdownText = nil
      self.isShiftActive = false
      self.shiftProgress = 0
      self.finalShiftCountdownSeconds = nil
    }

    // Update payroll countdown
    if let payrollDate = payrollDate {
      let (text, isPast, isToday) = CountdownFormatter.formatPayrollCountdown(
        payrollDate: payrollDate
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
    timerCancellable?.cancel()
  }
}
