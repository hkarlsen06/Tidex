#if DEBUG
  import SwiftUI

  /// Offline visual fixtures using production components. Launch with -ui-testing,
  /// TIDEX_UI_TEST_SCENARIO=design-review and TIDEX_DESIGN_SCREEN=<screen>.
  internal struct DesignReviewView: View {
    @State private var selectedDates: Set<String> = []
    @State private var selectionEnabled: Bool = false
    @State private var isPinned: Bool = true
    @StateObject private var paywallModel: PaywallViewModel = .init()
    @StateObject private var loginModel: LoginViewModel = .init()

    private let screen: String =
      ProcessInfo.processInfo.environment["TIDEX_DESIGN_SCREEN"] ?? "home"
    private let month: Date = Date.fromISODateString("2026-09-01") ?? .now

    internal var body: some View {
      Group {  // swiftlint:disable:this closure_body_length
        switch screen {
        case "settings":
          SettingsView()
            .environmentObject(AppCoordinator.shared)
        case "login":
          NavigationStack {
            LoginView(viewModel: loginModel, currency: "kr")
          }
        case "paywall":
          TrialPaywallScaffold(
            viewModel: paywallModel,
            showsAlternativeSection: false,
            showsRestorePurchases: true,
            onStartSubscription: { _ in },
            onRestorePurchases: {}
          ) {
            EmptyView()
          }
        default:
          NavigationStack {
            ScrollView {
              VStack(spacing: Spacing.lg) {
                switch screen {
                case "calendar": calendar
                case "stats": charts
                case "wagey": wagey
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
          isElevated: false
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

    private var wagey: some View {
      ChatMessageList(
        messages: [], streamingMessages: [], streamingContentBlocks: [],
        isStreaming: false, isThinking: false, remainingMessagesText: nil,
        showsHistoryButton: true, isScrolledToBottom: $isPinned
      )
      .frame(minHeight: 500)
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
#endif
