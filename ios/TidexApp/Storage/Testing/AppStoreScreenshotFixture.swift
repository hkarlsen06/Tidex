#if DEBUG
  import Supabase
  import SwiftData
  import SwiftUI

  /// Fictional, in-memory data for capturing the production screens without an account.
  /// This mode is unavailable in Release builds and on physical devices.
  internal enum AppStoreScreenshotFixture {
    nonisolated internal static var isActive: Bool {
      #if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
          && ProcessInfo.processInfo.environment["TIDEX_UI_TEST_SCENARIO"]
            == "app-store-screenshots"
      #else
        false
      #endif
    }

    internal static let userId: String = "00000000-0000-4000-8000-000000000027"
    // The screenshot UI test sets these per App Store locale.
    private static let environment: [String: String] = ProcessInfo.processInfo.environment
    internal static let displayName: String = environment["TIDEX_SCREENSHOT_NAME"] ?? "Emma"
    internal static let avatarURL: String? = environment["TIDEX_SCREENSHOT_AVATAR"].map {
      URL(fileURLWithPath: $0).absoluteString
    }
    private static let currency: String = environment["TIDEX_SCREENSHOT_CURRENCY"] ?? "kr"
    private static let hourlyWage: Double =
      environment["TIDEX_SCREENSHOT_HOURLY_WAGE"].flatMap(Double.init) ?? 225
    private static let supplementRate: Double =
      environment["TIDEX_SCREENSHOT_SUPPLEMENT"].flatMap(Double.init) ?? 25
    private static let jobId: String = "00000000-0000-4000-8000-000000000028"
    private static let fixtureDate: Date = Date(timeIntervalSince1970: 1_788_220_800)

    internal static var session: Session {
      guard let fixtureUserId: UUID = UUID(uuidString: userId) else {
        preconditionFailure("Invalid screenshot fixture UUID")
      }
      return Session(
        accessToken: "screenshot-fixture-not-a-token", tokenType: "bearer",
        expiresIn: 3_600, expiresAt: Date.now.timeIntervalSince1970 + 3_600,
        refreshToken: "screenshot-fixture-not-a-token",
        user: User(
          id: fixtureUserId, appMetadata: [:],
          userMetadata: ["full_name": .string(displayName)], aud: "authenticated",
          createdAt: fixtureDate, updatedAt: fixtureDate
        )
      )
    }

    @MainActor
    internal static func seed() throws {
      precondition(isActive)
      let context: ModelContext = LocalStore.shared.mainContext
      let settings: LocalUserSettings = .init(
        userId: userId, profilePictureUrl: avatarURL, payrollDay: 15, theme: "dark",
        aiDataSharingEnabled: true, currency: currency,
        wageyShowcaseSeen: true, serverUpdatedAt: fixtureDate, serverRevision: 1,
        lastSyncedSnapshot: Data(), localUpdatedAt: fixtureDate
      )
      context.insert(settings)
      context.insert(
        LocalJob(
          id: jobId, userId: userId, name: "Nord", currency: currency, isDefault: true,
          sortOrder: 0,
          payrollDay: 15, serverUpdatedAt: fixtureDate, serverRevision: 1,
          lastSyncedSnapshot: Data(), localUpdatedAt: fixtureDate
        ))
      context.insert(
        LocalWageSnapshot(
          id: "00000000-0000-4000-8000-000000000029", userId: userId, jobId: jobId,
          hourlyWage: hourlyWage,
          supplements: try kCanonicalJSONEncoder.encode(
            SupplementRulesSnapshot(rules: [
              SupplementRule(
                days: [1, 2, 3, 4, 5, 6, 7], from: "09:00", to: "17:00", rate: supplementRate)
            ])),
          taxEnabled: true, taxPercentage: 20, breakEnabled: false,
          serverUpdatedAt: fixtureDate, serverRevision: 1,
          lastSyncedSnapshot: Data(), localUpdatedAt: fixtureDate
        ))
      let today: DateComponents = Calendar(identifier: .gregorian).dateComponents(
        in: .current, from: .now)
      guard let year = today.year, let month = today.month, let day = today.day else { return }
      let days: Set<Int> = shiftDays(year: year, month: month, today: day)
      seedShifts(in: context, year: year, month: month, days: days)
      try context.save()
      showMonth(year: year, month: month, today: day, shiftDays: days)
    }

    @MainActor
    private static func showMonth(year: Int, month: Int, today: Int, shiftDays days: Set<Int>) {
      SharedMonthContext.shared.navigateTo(year: year, month: month)
      // Add a shift on the next free day, so the add screen does not warn about an overlap.
      let freeDay: Int =
        (today...daysIn(year: year, month: month)).first { !days.contains($0) }
        ?? (1...today).first { !days.contains($0) } ?? 1
      SharedMonthContext.shared.preselectedDate = String(
        format: "%04d-%02d-%02d", year, month, freeDay)
    }

    /// 14 shift days in the current month, one of them today. The screenshot UI test sets `TZ`
    /// so the local time is about 11:00, which puts today's 09:00 to 17:00 shift in progress.
    private static func shiftDays(year: Int, month: Int, today: Int) -> Set<Int> {
      let pattern: [Int] = [1, 3, 5, 9, 10, 12, 15, 17, 19, 22, 24, 26, 28, 30]
      var days: Set<Int> = Set(pattern.filter { $0 <= daysIn(year: year, month: month) })
      if !days.contains(today), let nearest = days.min(by: { abs($0 - today) < abs($1 - today) }) {
        days.remove(nearest)
        days.insert(today)
      }
      var extra: Int = 2
      while days.count < pattern.count {
        days.insert(extra)
        extra += 2
      }
      return days
    }

    private static func daysIn(year: Int, month: Int) -> Int {
      let calendar: Calendar = Calendar(identifier: .gregorian)
      guard let date = calendar.date(from: DateComponents(year: year, month: month)) else {
        return 28
      }
      return calendar.range(of: .day, in: .month, for: date)?.count ?? 28
    }

    /// The current month has 14 shifts and the eight months before it have 12 each.
    @MainActor
    private static func seedShifts(in context: ModelContext, year: Int, month: Int, days: Set<Int>) {
      for offset in 0...8 {
        let total: Int = year * 12 + month - 1 - offset
        let shiftYear: Int = total / 12
        let shiftMonth: Int = total % 12 + 1
        let monthDays: [Int] = offset == 0 ? days.sorted() : [2, 4, 6, 9, 11, 13, 16, 18, 20, 23, 25, 27]
        for day in monthDays {
          let dateString: String = String(format: "%04d-%02d-%02d", shiftYear, shiftMonth, day)
          guard let date: Date = Date.fromISODateString(dateString) else { continue }
          context.insert(
            LocalUserShift(
              id: "screenshot-\(dateString)", userId: userId, jobId: jobId,
              shiftDate: date, startTime: "09:00", endTime: "17:00",
              serverUpdatedAt: fixtureDate, serverRevision: 1,
              lastSyncedSnapshot: Data(), localUpdatedAt: fixtureDate
            ))
        }
      }
    }
  }

  internal struct AppStoreScreenshotView: View {
    @State private var isReady: Bool = false
    @State private var errorMessage: String?
    @State private var keyboardHideCount = 0

    internal var body: some View {
      Group {
        if let errorMessage {
          Text(errorMessage).accessibilityIdentifier("screenshot.error")
        } else if isReady {
          MainTabView()
            .environment(AppCoordinator.shared)
        } else {
          ProgressView()
        }
      }
      .overlay(alignment: .topLeading) {
        if ProcessInfo.processInfo.environment["TIDEX_TEST_KEYBOARD"] == "1" {
          Text(verbatim: String(keyboardHideCount))
            .accessibilityIdentifier("ui-testing.keyboard-hide-count")
            .allowsHitTesting(false)
            .onReceive(
              NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
              keyboardHideCount += 1
            }
        }
      }
      .task {
        guard AppStoreScreenshotFixture.isActive, !isReady else { return }
        do {
          try AppStoreScreenshotFixture.seed()
          isReady = true
        } catch {
          errorMessage = error.localizedDescription
        }
      }
    }
  }
#endif
