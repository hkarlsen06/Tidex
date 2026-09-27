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
          userMetadata: ["full_name": .string("Alex")], aud: "authenticated",
          createdAt: fixtureDate, updatedAt: fixtureDate
        )
      )
    }

    @MainActor
    internal static func seed() throws {
      precondition(isActive)
      let context: ModelContext = LocalStore.shared.mainContext
      let settings: LocalUserSettings = .init(
        userId: userId, payrollDay: 15, theme: "dark", aiDataSharingEnabled: true, currency: "kr",
        wageyShowcaseSeen: true, serverUpdatedAt: fixtureDate, serverRevision: 1,
        lastSyncedSnapshot: Data(), localUpdatedAt: fixtureDate
      )
      context.insert(settings)
      context.insert(
        LocalJob(
          id: jobId, userId: userId, name: "Nord", isDefault: true, sortOrder: 0,
          payrollDay: 15, serverUpdatedAt: fixtureDate, serverRevision: 1,
          lastSyncedSnapshot: Data(), localUpdatedAt: fixtureDate
        ))
      context.insert(
        LocalWageSnapshot(
          id: "00000000-0000-4000-8000-000000000029", userId: userId, jobId: jobId,
          hourlyWage: 225,
          supplements: try kCanonicalJSONEncoder.encode(
            SupplementRulesSnapshot(rules: [
              SupplementRule(days: [1, 2, 3, 4, 5, 6, 7], from: "09:00", to: "17:00", rate: 25)
            ])),
          taxEnabled: true, taxPercentage: 20, breakEnabled: false,
          serverUpdatedAt: fixtureDate, serverRevision: 1,
          lastSyncedSnapshot: Data(), localUpdatedAt: fixtureDate
        ))
      seedShifts(in: context)
      try context.save()
      SharedMonthContext.shared.navigateTo(year: 2_026, month: 9)
      SharedMonthContext.shared.preselectedDate = "2026-09-21"
    }

    @MainActor
    private static func seedShifts(in context: ModelContext) {
      for month in 1...9 {
        let days: [Int] =
          month == 9
          ? [1, 3, 5, 9, 10, 12, 15, 17, 19, 22, 24, 26, 28, 30]
          : [2, 4, 6, 9, 11, 13, 16, 18, 20, 23, 25, 27]
        for day in days {
          let dateString: String = String(format: "2026-%02d-%02d", month, day)
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
            .environmentObject(AppCoordinator.shared)
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
