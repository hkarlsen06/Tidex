#if DEBUG
  import SwiftUI

  /// Offline visual fixtures using production components. Launch with -ui-testing,
  /// TIDEX_UI_TEST_SCENARIO=design-review and TIDEX_DESIGN_SCREEN=<screen>.
  internal struct DesignReviewView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDates: Set<String> = []
    @State private var selectionEnabled: Bool = false
    @State private var startTime: Date? = EventSheetFormatter.date(from: "09:00")
    @State private var endTime: Date? = EventSheetFormatter.date(from: "17:00")
    @State private var showingShiftEditor: Bool = false
    @State private var payReviewDate = Date.fromISODateString("2026-11-15") ?? .now
    @State private var isPayReviewExpanded = false
    @State private var payEditorSelection: PayEditorSelection?
    @State private var savedPayDescription = ""
    @State private var loginModel: LoginViewModel = .init()
    @State private var signupModel: SignupViewModel = .init()

    private let screen: String =
      ProcessInfo.processInfo.environment["TIDEX_DESIGN_SCREEN"] ?? "home"
    private let month: Date = Date.fromISODateString("2026-09-01") ?? .now

    private struct PayEditorSelection: Identifiable {
      let id = UUID()
      let snapshot: WageSnapshot?
      let section: WageSnapshotEditorSection?
    }

    internal var body: some View {
      Group {  // swiftlint:disable:this closure_body_length
        switch screen {
        case "friends":
          DesignReviewFriendCards()
        case "money", "money-payroll":
          DesignReviewMoneyCards(screen: screen)
        case "settings":
          SettingsView()
            .environment(AppCoordinator.shared)
        case "login", "login-accessibility":
          NavigationStack {
            LoginView(viewModel: loginModel, currency: "kr")
          }
          .dynamicTypeSize(screen == "login-accessibility" ? .accessibility5 : dynamicTypeSize)
        case "signup":
          SignupView(viewModel: signupModel, currency: "kr")
        case "time-input", "time-input-accessibility":
          NavigationStack {
            ScrollView {
              TimeRangePicker(
                startTime: $startTime,
                endTime: $endTime,
                presetRanges: [TimeRangeCount(startTime: "09:00", endTime: "17:00", count: 1)]
              )
              .padding(Spacing.mlg)
            }
            .background(Color.tidexBackground)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: .commonSave)) {}
                  .disabled(startTime == nil || endTime == nil)
              }
            }
          }
          .dynamicTypeSize(screen == "time-input-accessibility" ? .accessibility5 : dynamicTypeSize)
        case "shift-editor":
          Button(String(localized: .shiftsActionsEdit)) {
            showingShiftEditor = true
          }
          .sheet(isPresented: $showingShiftEditor) {
            ShiftDetailsSheet(shift: Self.shifts[0], onUpdate: { _ in }, startInEditMode: true)
              .environment(AppCoordinator.shared)
          }
        case "payroll-breakdown":
          ShiftDetailsSheet(shift: Self.payrollBreakdownShift, jobName: "Harbour")
            .environment(AppCoordinator.shared)
        case "pay-settings-review", "pay-settings-accessibility":
          paySettingsReview
            .dynamicTypeSize(
              screen == "pay-settings-accessibility" ? .accessibility3 : dynamicTypeSize)
        case "pay-history-tariff-editor":
          if savedPayDescription.isEmpty {
            WageSnapshotEditorSheet(
              mode: .edit, snapshot: Self.savedTariffSnapshot,
              snapshots: [Self.savedTariffSnapshot],
              initialSection: .tax,
              onSave: { input in
                savedPayDescription =
                  "\(input.hourlyWage)|\(input.supplements.rules.count)|\(input.taxEnabled)"
                return true
              }, onDelete: { _ in }, onCancel: {}
            )
          } else {
            Text(verbatim: savedPayDescription).accessibilityIdentifier("pay-history.saved-result")
          }
        case "job-pay-setup":
          if savedPayDescription.isEmpty {
            JobPaySetupSheet(job: Self.payReviewJob, initialCurrency: "$") { input in
              savedPayDescription =
                "\(input.baselineSnapshot.breakEnabled ?? false)|\(input.baselineSnapshot.taxEnabled ?? false)"
              return true
            }
          } else {
            Text(verbatim: savedPayDescription).accessibilityIdentifier("pay-history.saved-result")
          }
        case "add-job-setup":
          if savedPayDescription.isEmpty {
            AddJobSheet(initialCurrency: "$", prefilledBasicJob: Self.payReviewJob) { input in
              savedPayDescription =
                "\(input.baselineSnapshot.breakEnabled ?? false)|\(input.baselineSnapshot.taxEnabled ?? false)"
              return true
            }
          } else {
            Text(verbatim: savedPayDescription).accessibilityIdentifier("pay-history.saved-result")
          }
        default:
          NavigationStack {
            ScrollView {
              VStack(spacing: Spacing.lg) {
                switch screen {
                case "calendar": calendar
                case "shared-calendar": sharedCalendar
                case "stats": charts
                case "controls": controls
                default: dashboard
                }
              }
              .padding(Spacing.mlg)
            }
            .background(Color.tidexBackground)
            .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
          }
        }
      }
      .userCurrency("kr")
      .tint(.tidexBlue)
    }

    private var dashboard: some View {
      VStack(spacing: Spacing.lg) {
        TotalCard(
          gross: 28_400, net: 22_720, completedGross: 12_200, completedNet: 9_760,
          shiftCount: 14, plannedCount: 8, percentageChange: 12, taxEnabled: true,
          monthName: "September", isElevated: false
        )
        PayrollCard(
          payrollDate: month.addingTimeInterval(14 * 86_400),
          label: String(localized: .dashboardNextPayout), gross: 24_600,
          net: 19_680, tax: 4_920, taxEnabled: true, isElevated: false
        )
        FeaturedShiftCard(
          shift: Self.shifts[0], isToday: false, isBestShift: false,
          countdownText: nil, surfaceStyle: .flat
        )
        ForEach(Self.shifts.prefix(2)) { shift in
          ShiftRowCard(shift: shift, isToday: false)
        }
        PrimaryButton(title: String(localized: .commonContinue), action: {})
      }
    }

    private var paySettingsReview: some View {
      let entries = WageTimelineProcessor.processSnapshots(
        Self.payReviewSnapshots, locale: .appLocale, currency: "kr",
        today: Date.fromISODateString("2026-11-15") ?? .now)
      return NavigationStack {
        ScrollView {
          VStack(spacing: Spacing.lg) {
            PaySettingsReviewCard(
              isExpanded: $isPayReviewExpanded,
              workDate: $payReviewDate, snapshots: Self.payReviewSnapshots, entries: entries,
              currency: "kr", payrollDay: 15, halfTaxMonth: 12,
              onEdit: { snapshot, section in
                payEditorSelection = PayEditorSelection(snapshot: snapshot, section: section)
              })
            WageHistoryTimelineView(
              entries: entries, currency: "kr",
              onAddNew: {
                payEditorSelection = PayEditorSelection(snapshot: nil, section: nil)
              },
              onEdit: { snapshot in
                payEditorSelection = PayEditorSelection(snapshot: snapshot, section: nil)
              })
            if !savedPayDescription.isEmpty {
              Text(verbatim: savedPayDescription).accessibilityIdentifier(
                "pay-history.saved-result")
            }
          }
          .padding(Spacing.md)
        }
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .settingsPayTitle))
        .navigationBarTitleDisplayMode(.inline)
      }
      .sheet(item: $payEditorSelection) { selection in
        WageSnapshotEditorSheet(
          mode: selection.snapshot == nil ? .create : .edit,
          snapshot: selection.snapshot, snapshots: Self.payReviewSnapshots,
          initialDate: payReviewDate,
          initialSection: selection.section,
          onSave: { input in
            savedPayDescription =
              "\(input.hourlyWage)|\(input.fromDate?.toISODateString() ?? "baseline")"
            payEditorSelection = nil
            return true
          }, onDelete: { _ in }, onCancel: { payEditorSelection = nil }
        )
        .dynamicTypeSize(screen == "pay-settings-accessibility" ? .accessibility3 : dynamicTypeSize)
      }
    }

    private static var payReviewJob: Job {
      Job(
        id: "pay-review", user_id: "design-preview", name: "Harbour", color: nil, currency: "$",
        is_default: true, sort_order: 0, payroll_day: 15, half_tax_month: 12, monthly_goal: nil,
        archived_at: nil, deleted_at: nil, created_at: nil, updated_at: nil)
    }

    private static var payReviewSnapshots: [WageSnapshot] {
      [
        payReviewSnapshot(id: "future", date: "2026-12-01", wage: 250, tax: 30),
        payReviewSnapshot(id: "baseline", date: nil, wage: 200, tax: 20),
      ]
    }

    private static var savedTariffSnapshot: WageSnapshot {
      WageSnapshot(
        id: "saved-tariff", user_id: "design-preview", from_date: nil,
        hourly_wage: 184.12, wage_level: 1, tariff_type_id: "hk_retail",
        supplements: SupplementRulesSnapshot(rules: [
          SupplementRule(days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 11.25)
        ]), tax_enabled: false, tax_percentage: 20, break_enabled: false,
        break_method: "proportional", break_threshold_hours: 5.5,
        break_deduction_minutes: 30, created_at: nil)
    }

    private static func payReviewSnapshot(id: String, date: String?, wage: Double, tax: Double)
      -> WageSnapshot
    {
      WageSnapshot(
        id: id, user_id: "design-preview", job_id: "pay-review", from_date: date,
        hourly_wage: wage, wage_level: nil, tariff_type_id: nil,
        supplements: SupplementRulesSnapshot(rules: []), tax_enabled: true, tax_percentage: tax,
        break_enabled: true, break_method: "proportional", break_threshold_hours: 5.5,
        break_deduction_minutes: 30, created_at: nil)
    }

    private var calendar: some View {
      ShiftsCalendarView(
        shifts: Self.shifts,
        presentation: .build(
          shifts: Self.shifts, year: 2_026, month: 9, jobs: [], currency: "kr",
          excludedFromTotalIds: []
        ),
        month: month, year: 2_026, monthNumber: 9, currency: "kr",
        showEarnings: true, jobs: [], selectedDates: $selectedDates,
        confirmingDelete: false, isDeleting: false, selectedEarnings: nil,
        selectedCurrencyAggregate: nil, selectedHasTaxEnabled: true,
        isCopyMode: false, isMoveMode: false, isCopying: false, isMoving: false,
        isSelectionModeEnabled: $selectionEnabled
      )
    }

    private var charts: some View {
      VStack(spacing: Spacing.lg) {
        MonthlyProgressChart(
          data: (1...30).map { day in
            DailyCumulativeData(
              day: day, currentMonth: Double(day / 2) * 1_600,
              lastMonth: Double(day / 3) * 2_000, isToday: day == 12, isFuture: day > 12
            )
          })
        YearlyIncomeChart(data: MonthlyIncomeData.previewData, focusYear: 2_026)
      }
    }

    private var controls: some View {
      VStack(spacing: Spacing.lg) {
        PrimaryButton(title: String(localized: .oauthContinueWithApple), action: {})
        PrimaryButton(
          title: String(localized: .oauthContinueWithApple), action: {}, isLoading: true
        )
        PrimaryButton(
          title: String(localized: .oauthContinueWithApple), action: {}, isDisabled: true
        )
      }
    }

    private static var payrollBreakdownShift: ShiftWithComputations {
      let row = ShiftRow(
        id: "design-payroll", user_id: "design-preview",
        shift_date: "2026-02-07", start_time: "22:00", end_time: "02:00", custom_supplements: nil
      )
      let snapshot = WageSnapshot(
        id: "design-wage", user_id: "design-preview", from_date: nil,
        hourly_wage: 200, wage_level: nil, tariff_type_id: nil,
        supplements: SupplementRulesSnapshot(rules: [
          SupplementRule(days: [6], from: "18:00", to: "24:00", rate: 50),
          SupplementRule(days: [7], from: "00:00", to: "24:00", rate: 100),
        ]),
        overtime: OvertimeConfig(
          enabled: true, weeklyThresholdHours: 1,
          rules: OvertimeConfig.seededDefaults.rules),
        tax_enabled: false, tax_percentage: 0, break_enabled: true,
        break_method: "end_of_shift", break_threshold_hours: 0,
        break_deduction_minutes: 30, created_at: nil
      )
      return PayrollEngine.computeShiftsForMonth(
        .init(
          year: 2026, month: 2, shifts: [row], recurring: [], snapshots: [snapshot],
          settings: nil, jobs: []
        ))[0]
    }

    private static var shifts: [ShiftWithComputations] {
      [8, 10, 12, 15, 17, 19, 22, 24, 26].map { day in
        let row: ShiftRow = .init(
          id: "design-\(day)", user_id: nil,
          shift_date: String(format: "2026-09-%02d", day),
          start_time: "09:00", end_time: "17:00", custom_supplements: nil
        )
        let snapshot: WageSnapshot = .init(
          id: "design-wage", user_id: "design-preview", from_date: nil,
          hourly_wage: 250, wage_level: nil, tariff_type_id: nil,
          supplements: SupplementRulesSnapshot(rules: []),
          tax_enabled: true, tax_percentage: 20, break_enabled: false,
          break_method: BreakMethod.proportional.rawValue, break_threshold_hours: 5.5,
          break_deduction_minutes: 30, created_at: nil
        )
        return ShiftWithComputations(
          shift: row, computed: PayrollCalculator.computeShift(row, snapshot: snapshot),
          taxEnabled: true, taxPercentage: 20
        )
      }
    }
  }

  extension DesignReviewView {
    /// Friend's shifts from `shifts`, overlaid with the viewer's own shifts, including an
    /// overnight one and two on Mondays so week numbers and person indicators share a cell.
    var sharedCalendar: some View {
      let userShifts: [ShiftRow] = [
        (7, "09:00", "17:00"), (8, "12:00", "20:00"), (14, "22:00", "06:00"),
        (28, "09:00", "17:00"),
      ].map { day, start, end in
        ShiftRow(
          id: "design-own-\(day)", user_id: nil, shift_date: String(format: "2026-09-%02d", day),
          start_time: start, end_time: end, custom_supplements: nil)
      }
      return SharedShiftsCalendarView(
        shifts: Self.shifts, jobs: [], year: 2_026, month: 9, currency: "kr",
        showEarnings: false, friendFirstName: "Sam", isSuperimposing: true,
        userHoursByDate: Dictionary(
          uniqueKeysWithValues: userShifts.map { row in
            (
              row.shift_date,
              HoursData(
                start: row.start_time, end: row.end_time,
                crossesMidnight: row.end_time < row.start_time)
            )
          }),
        userShiftsByDate: Dictionary(grouping: userShifts, by: \.shift_date)
      )
    }
  }
#endif
