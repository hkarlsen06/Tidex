import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SharedShiftsListView")

/// List of shared shifts from a specific sharer for the selected month
struct SharedShiftsListView: View {
  let sharer: SharedUser
  let shifts: [ShiftWithComputations]
  let jobs: [SharedJob]
  let year: Int
  let month: Int
  let phase: MonthTransitionPhase?
  let isLoading: Bool
  let isContentReady: Bool

  /// Dates to highlight from notification deeplink
  var highlightDates: Set<String> = []

  /// Shift IDs to highlight from notification deeplink (more precise than dates)
  var highlightShiftIds: Set<String> = []

  /// Whether superimpose mode is active
  var isSuperimposing: Bool = false

  /// User's own shift hours by date (for superimpose feature)
  var userHoursByDate: [String: HoursData]?

  /// User's own raw shifts by date (for precise overlap indicators)
  var userShiftsByDate: [String: [ShiftRow]]?

  /// User's own earnings by date (for superimpose feature in earnings mode)
  var userEarningsByDate: [String: CalendarEarningsData]?

  var onPreviousMonth: (() -> Void)?
  var onNextMonth: (() -> Void)?

  var onSendToChatCompleted: ((SendShiftToChatResult) -> Void)?

  @Environment(\.userCurrency) private var currency
  @Environment(\.isSceneCaptured) private var isSceneCaptured
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var emptyIconSize: CGFloat = 48

  // View mode toggle (synced with Shifts tab)
  @AppStorage("shiftsViewMode") private var showListView = false

  // Sheet state for shift details (using item-based presentation to fix first-tap bug)
  @State private var selectedShift: ShiftWithComputations?
  @State private var pendingSendToChatResult: SendShiftToChatResult?

  // Screenshot bubble state
  @State private var screenshotFeedback = ScreenshotNotificationFeedback()

  private var jobsById: [String: SharedJob] {
    Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
  }

  private var showJobIndicator: Bool {
    jobs.count > 1
  }

  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  var body: some View {
    GeometryReader { _ in
      ZStack {
        TidexAppBackground()

        if !isContentReady, shifts.isEmpty {
          Color.clear
        } else if isLoading, shifts.isEmpty {
          loadingState
        } else if showListView {
          shiftListContent
        } else {
          calendarContent
        }

        screenshotBubbleOverlay
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.none, value: showListView)
    // Using .sheet(item:) guarantees data availability when sheet presents
    .sheet(
      item: $selectedShift,
      onDismiss: {
        guard let pendingSendToChatResult else { return }
        self.pendingSendToChatResult = nil
        onSendToChatCompleted?(pendingSendToChatResult)
      }
    ) { shift in
      let shiftJob = showJobIndicator ? shift.shift.job_id.flatMap { jobsById[$0] } : nil
      ShiftDetailsSheet(
        shift: shift,
        jobName: shiftJob?.name,
        jobColorHex: shiftJob?.color,
        onDelete: nil,
        onSendToChatCompleted: { result in
          pendingSendToChatResult = result
          selectedShift = nil
        },
        snapshotShareContext: .shared(owner: sharer)
      )
      .userCurrency(shiftJob?.currency ?? currency)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    // Detect screenshots and notify the sharer
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
    ) { _ in
      Task {
        await reportScreenshot()
      }
    }
    .onChange(of: isSceneCaptured) { wasCaptured, isCaptured in
      guard isCaptured, !wasCaptured else { return }
      Task {
        await reportScreenshot()
      }
    }
  }
}

extension SharedShiftsListView {
  // MARK: - Calendar View

  /// Centers the calendar vertically like in ShiftsView
  private var calendarContent: some View {
    VStack {
      Spacer()
      calendarView
        .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
      Spacer()
    }
    // Offset for month picker overlay so content centers in available space
    .padding(.bottom, MonthPickerLayout.totalBottomInset)
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.15), value: isSuperimposing)
  }

  private var calendarView: some View {
    SharedShiftsCalendarView(
      shifts: shifts,
      jobs: jobs,
      year: year,
      month: month,
      phase: phase,
      currency: currency,
      showEarnings: sharer.showEarnings,
      friendFirstName: sharer.firstNameOnly,
      highlightDates: highlightDates,
      highlightShiftIds: highlightShiftIds,
      isSuperimposing: isSuperimposing,
      userHoursByDate: userHoursByDate,
      userShiftsByDate: userShiftsByDate,
      userEarningsByDate: userEarningsByDate,
      onShiftTapped: { shift in
        selectedShift = shift
      },
      onSwipeLeft: {
        AppearanceTracker.shared.reset()
        onNextMonth?()
      },
      onSwipeRight: {
        AppearanceTracker.shared.reset()
        onPreviousMonth?()
      }
    )
  }

  @ViewBuilder
  private var screenshotBubbleOverlay: some View {
    if screenshotFeedback.showsBubble {
      VStack {
        screenshotBubble
          .onTapGesture {
            dismissScreenshotBubble()
          }
          .accessibilityAddTraits(.isButton)
          .transition(
            .asymmetric(
              insertion: reduceMotion ? .opacity : .scale.combined(with: .opacity),
              removal: .opacity
            ))
        Spacer()
      }
      .padding(.top, Spacing.md)
    }
  }

  // MARK: - List View

  /// Shifts grouped by ISO week for list display
  private var weekGroups:
    [(weekKey: String, weekNumber: Int, totalGross: Double, shifts: [ShiftWithComputations])]
  {
    var calendar = Calendar(identifier: .iso8601)
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4

    var weekMap: [String: (weekNumber: Int, totalGross: Double, shifts: [ShiftWithComputations])] =
      [:]

    for shift in shifts {
      guard let date = Date.fromISODateString(shift.shiftDate) else { continue }
      let weekOfYear = calendar.component(.weekOfYear, from: date)
      let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
      let weekKey = "\(yearForWeek)-W\(String(format: "%02d", weekOfYear))"
      let gross = shift.taxEnabled ? shift.netPay : shift.grossPay

      if var existing = weekMap[weekKey] {
        existing.shifts.append(shift)
        existing.totalGross += gross
        weekMap[weekKey] = existing
      } else {
        weekMap[weekKey] = (weekNumber: weekOfYear, totalGross: gross, shifts: [shift])
      }
    }

    return weekMap.map {
      (
        weekKey: $0.key, weekNumber: $0.value.weekNumber, totalGross: $0.value.totalGross,
        shifts: $0.value.shifts
      )
    }
    .sorted { $0.weekKey < $1.weekKey }
  }

  @ViewBuilder
  private var shiftListContent: some View {
    if shifts.isEmpty {
      VStack(spacing: Spacing.md) {
        Image(systemName: "calendar.badge.minus")
          .font(.system(size: emptyIconSize))
          .foregroundColor(.tidexTextMuted)
          .accessibilityHidden(true)
        Text(.shiftsEmptyNoShiftsThisMonth)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List {
        ForEach(weekGroups, id: \.weekKey) { weekGroup in
          Section {
            ForEach(weekGroup.shifts) { shift in
              let shiftJob = shift.shift.job_id.flatMap { jobsById[$0] }
              let rowCurrency = shiftJob?.currency ?? currency
              ShiftRowCard(
                shift: shift,
                isToday: shift.shiftDate == todayISO(),
                showJobIndicator: showJobIndicator,
                jobName: shiftJob?.name,
                jobColorHex: shiftJob?.color,
                amountTextOverride: sharer.showEarnings
                  ? nil
                  : CurrencyConfig.formatEmpty(currency: rowCurrency),
                onTap: { selectedShift = shift }
              )
              .userCurrency(rowCurrency)
              .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
            }
          } header: {
            WeekHeaderView(
              weekNumber: weekGroup.weekNumber,
              totalGross: weekGroup.totalGross,
              totalGrossTextOverride: sharer.showEarnings
                ? nil
                : CurrencyConfig.formatEmpty(currency: currency)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
      .contentMargins(.bottom, MonthPickerLayout.totalBottomInset + Spacing.md, for: .scrollContent)
      .refreshable {
        // Pull-to-refresh is a no-op here; shifts are fetched by the parent
      }
    }
  }

  // MARK: - Screenshot Detection

  /// Reports to the sharer that their shifts were captured
  private func reportScreenshot() async {
    // Debug builds ignore screenshots so development screenshots don't notify sharers
    #if DEBUG
      return
    #else
      logger.info("Screen capture detected while viewing \(sharer.firstName ?? "friend")'s shifts")

      screenshotFeedback.showBubble()

      do {
        try await ScreenshotNotificationService.shared.reportScreenshot(sharerId: sharer.id)
        logger.info("Screenshot notification sent successfully")
        await screenshotFeedback.markSent()
      } catch {
        // Silently fail - don't interrupt user experience for notification failures
        logger.error("Failed to report screenshot: \(error.localizedDescription)")
      }
    #endif
  }

  /// Dismisses the screenshot bubble
  private func dismissScreenshotBubble() {
    screenshotFeedback.dismiss()
  }

  /// Screenshot notification bubble (matches SyncStatusIndicator styling)
  private var screenshotBubble: some View {
    ScreenshotNotificationBubble(
      notifiedName: sharer.firstNameOnly,
      showNotifiedIcon: screenshotFeedback.showsNotifiedIcon,
      bellShakeTrigger: screenshotFeedback.bellShakeTrigger
    )
  }

  // MARK: - States

  private var loadingState: some View {
    VStack(spacing: Spacing.md) {
      ProgressView()
        .scaleEffect(1.2)

      Text(.sharingLoadingShifts)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 60)
  }
}

#Preview {
  SharedShiftsListView(
    sharer: SharedUser(
      id: "1",
      email: "john@example.com",
      phone: nil,
      firstName: "John Doe",
      profilePictureUrl: nil,
      oauthAvatarUrl: nil,
      sharedAt: "2025-01-01",
      showEarnings: true,
      hidden: false
    ),
    shifts: [],
    jobs: [],
    year: 2_025,
    month: 1,
    phase: nil,
    isLoading: false,
    isContentReady: true
  )
  .background(Color.tidexBackground)
  .environment(\.userCurrency, "kr")
}
