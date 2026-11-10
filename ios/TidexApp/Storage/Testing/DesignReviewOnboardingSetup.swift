#if DEBUG
  import SwiftUI

  /// Walks the real setup screens without creating an account or saving a job.
  /// `TIDEX_DESIGN_RESULT` picks the result screen: `carried` (default), `carried-multi`,
  /// `ready`, `saving`, `failed` or `shift-failed`. `TIDEX_DESIGN_FRIENDS=failed` makes the
  /// friends choice fail on the purpose screen.
  internal struct DesignReviewOnboardingSetup: View {
    private enum Step {
      case purpose
      case job
      case wage
      case result
    }

    @State private var data = OnboardingData()
    @State private var step: Step = .purpose
    @State private var status: OnboardingSaveManager.SaveStatus = .idle
    @State private var friendsStatus: OnboardingSaveManager.SaveStatus = .idle
    @State private var shiftStatus: OnboardingSaveManager.SaveStatus = .idle
    @State private var carriedShiftPay: CarriedShiftPay?

    private let resultCase: String =
      ProcessInfo.processInfo.environment["TIDEX_DESIGN_RESULT"] ?? "carried"
    private let friendsFail: Bool =
      ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS"] == "failed"

    internal var body: some View {
      Group {
        switch step {
        case .purpose:
          PurposeScreen(
            currency: data.currency,
            friendsSaveStatus: friendsStatus,
            onSelectPaySetup: { step = .job },
            onSelectFriendsOnly: selectFriends
          )
        case .job:
          JobBasicsOnboardingScreen(data: data, onContinue: { step = .wage }, onBack: { step = .purpose })
        case .wage:
          WageScreen(
            data: data,
            onContinue: showResult,
            onBack: { step = .job },
            stepLabel: .onboardingPostAuthStep(2, 2)
          )
        case .result:
          SetupResultScreen(
            status: status,
            carriedShiftPay: carriedShiftPay,
            carriedShiftStatus: shiftStatus,
            onRetry: { status = .success },
            onBack: { step = .wage },
            onSaveCarriedShift: saveShift,
            onDeclineCarriedShift: restart,
            onAddFirstShift: restart,
            onFinish: restart
          )
        }
      }
      .userCurrency(data.currency)
    }

    private func selectFriends() {
      friendsStatus =
        friendsFail
        ? .error(message: String(localized: .onboardingSuccessErrorMessage)) : .saving
    }

    private func showResult() {
      if data.usesSimpleSetup {
        data.applySimpleSetupDefaults()
      }
      switch resultCase {
      case "saving":
        status = .saving
      case "failed":
        status = .error(message: String(localized: .onboardingSuccessErrorMessage))
      default:
        status = .success
      }
      carriedShiftPay =
        resultCase == "ready"
        ? nil
        : CarriedShiftPay(shift: carriedShift, snapshots: [snapshot], currency: data.currency)
      step = .result
    }

    private func saveShift() {
      if resultCase == "shift-failed", shiftStatus != .error(message: shiftFailure) {
        shiftStatus = .error(message: shiftFailure)
        return
      }
      shiftStatus = .success
      restart()
    }

    private func restart() {
      shiftStatus = .idle
      step = .purpose
    }

    private var shiftFailure: String {
      String(localized: .onboardingSuccessShiftSaveFailed)
    }

    /// Tomorrow evening, or the last evening of this month and the first of the next.
    private var carriedShift: CarriedDemoShift {
      let calendar = Calendar.current
      let today = Date()
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
      guard resultCase == "carried-multi",
        let nextMonth = calendar.dateInterval(of: .month, for: today)?.end,
        let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth)
      else {
        return CarriedDemoShift(
          dates: [tomorrow.toISODateString()], startTime: "16:00", endTime: "21:00")
      }
      return CarriedDemoShift(
        dates: [lastDay.toISODateString(), nextMonth.toISODateString()],
        startTime: "16:00", endTime: "22:00")
    }

    /// The baseline wage setup would save, built from the same values.
    private var snapshot: WageSnapshot {
      WageSnapshot(
        id: "design-review-setup",
        user_id: "design-review",
        from_date: nil,
        hourly_wage: data.resolvedHourlyWage,
        wage_level: data.resolvedWageLevel,
        tariff_type_id: data.resolvedTariffTypeId,
        supplements: data.resolvedSupplements,
        overtime: data.resolvedOvertime,
        tax_enabled: data.taxEnabled,
        tax_percentage: data.taxEnabled ? data.taxPercentage : nil,
        break_enabled: data.breakEnabled,
        break_method: BreakMethod.proportional.rawValue,
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
        created_at: nil
      )
    }
  }
#endif
