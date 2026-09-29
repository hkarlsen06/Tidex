// swiftlint:disable conditional_returns_on_newline file_length type_body_length
// swiftlint:disable:previous blanket_disable_command
#if DEBUG
  import os.log
  import SwiftUI
  import UserNotifications

  private let logger = Logger(subsystem: "com.tidex.app", category: "SyncDebugView")

  // MARK: - Debug View

  /// Debug view for testing app functionality
  /// Accessible from user menu > Debug (only in debug builds)
  struct SyncDebugView: View {
    @State private var testHelper = SyncTestHelper.shared
    private let syncCoordinator = SyncCoordinator.shared

    @State private var userId: String?
    @State private var syncStateSummary: SyncStateSummary?
    @State private var validationResults: [ValidationResult] = []
    @State private var isRunningValidation = false
    @State private var isLoadingSummary = false
    @State private var showAdvancedSync = false
    @State private var showResetLocalDataConfirmation = false

    // Notification debug state
    @State private var pendingSmartCount = 0
    @State private var pendingReminderCount = 0
    @State private var scheduledNotifications: [(id: String, fireDate: Date?)] = []
    @State private var workPatternResult: WorkPatternAnalyzer.AnalysisResult?
    @State private var testNotificationResult: String?

    var body: some View {
      List {
        Group {
          // Quick Actions (most used)
          quickActionsSection

          // Notifications Section
          notificationsSection

          // Sync Status Section
          syncStatusSection

          // Advanced controls
          advancedSection

          // Advanced Sync (collapsible)
          if showAdvancedSync {
            stateSummarySection
            validationSection
            logsSection
          }

          // Destructive actions
          dangerZoneSection
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
      .tidexListBackground()
      .navigationTitle("Debug")
      .task {
        await loadUserId()
      }
      .refreshable {
        await reloadDebugData()
      }
      .alert("Reset Local Data?", isPresented: $showResetLocalDataConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Reset", role: .destructive) {
          Task { await resetLocalData() }
        }
      } message: {
        Text("This removes all local data and sync state on this device.")
      }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
      Section("Notifications") {
        workPatternRow

        // Pending notification counts
        HStack {
          Text("Smart Notifications")
          Spacer()
          Text("\(pendingSmartCount) pending")
            .foregroundColor(pendingSmartCount > 0 ? .green : .secondary)
        }

        HStack {
          Text("Shift Reminders")
          Spacer()
          Text("\(pendingReminderCount) pending")
            .foregroundColor(pendingReminderCount > 0 ? .green : .secondary)
        }

        scheduledNotificationRows

        sendTestNotificationMenu

        notificationActions
      }
    }

    @ViewBuilder
    private var notificationActions: some View {
      Button {
        guard let userId else { return }
        Task {
          await SmartNotificationScheduler.shared.scheduleSmartNotifications(for: userId)
          testNotificationResult = "Rescheduled"
          await loadNotificationState()
        }
      } label: {
        Label("Reschedule Smart Notifications", systemImage: "arrow.clockwise")
      }
      .disabled(userId == nil)

      Button {
        Task { await loadNotificationState() }
      } label: {
        Label("Reload Notification State", systemImage: "arrow.clockwise.circle")
      }

      if let result = testNotificationResult {
        Text(result)
          .font(.caption)
          .foregroundColor(result.contains("Failed") ? .red : .green)
      }
    }

    private var workPatternRow: some View {
      HStack {
        Text("Work Pattern")
        Spacer()
        if let result = workPatternResult {
          switch result {
          case .success(let pattern):
            Text("\(pattern.typicalWorkDays.count) work days")
              .foregroundColor(.green)

          case .insufficientData(let weeksFound):
            Text("\(weeksFound)/\(WorkPatternAnalyzer.WorkPattern.minimumWeeksRequired) weeks")
              .foregroundColor(.orange)

          case .noShifts:
            Text("No shifts")
              .foregroundColor(.red)

          case .noPatternDetected:
            Text("No pattern")
              .foregroundColor(.orange)
          }
        } else {
          Text("Not loaded")
            .foregroundColor(.secondary)
        }
      }
    }

    @ViewBuilder
    private var scheduledNotificationRows: some View {
      if !scheduledNotifications.isEmpty {
        ForEach(scheduledNotifications, id: \.id) { notification in
          HStack {
            let label = notificationLabel(for: notification.id)
            Image(systemName: label.icon)
              .font(.caption)
              .foregroundColor(label.color)
              .frame(width: 16)

            Text(label.text)
              .font(.caption)
              .foregroundColor(.primary)

            Spacer()

            if let fireDate = notification.fireDate {
              Text(fireDate, style: .relative)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
            } else {
              Text("—")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }
    }

    private var sendTestNotificationMenu: some View {
      Menu {
        Button("Send Morning Test") {
          Task {
            let success = await SmartNotificationScheduler.shared.scheduleTestNotification(
              type: .morning
            )
            testNotificationResult =
              success ? "Morning test scheduled (5s)" : "Failed to schedule"
          }
        }

        Button("Send Evening Test") {
          Task {
            let success = await SmartNotificationScheduler.shared.scheduleTestNotification(
              type: .evening
            )
            testNotificationResult =
              success ? "Evening test scheduled (5s)" : "Failed to schedule"
          }
        }
      } label: {
        Label("Send Test Notification", systemImage: "paperplane")
      }
    }

    private func loadNotificationState() async {
      let center = UNUserNotificationCenter.current()
      let pending = await center.pendingNotificationRequests()

      let smartRequests = pending.filter { request in
        request.identifier.hasPrefix("smart-morning-")
          || request.identifier.hasPrefix(
            "smart-evening-")
          || request.identifier.hasPrefix("smart-test-")
      }
      pendingSmartCount = smartRequests.count

      let reminderRequests = pending.filter { request in
        request.identifier.hasPrefix("shift-reminder-")
      }
      pendingReminderCount = reminderRequests.count

      // Build sorted list of all smart + reminder notifications with fire dates
      let allRelevant = smartRequests + reminderRequests
      scheduledNotifications =
        allRelevant
        .map { request in
          let fireDate: Date?
          if let calTrigger = request.trigger as? UNCalendarNotificationTrigger {
            fireDate = calTrigger.nextTriggerDate()
          } else if let timeTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
            fireDate = timeTrigger.nextTriggerDate()
          } else {
            fireDate = nil
          }
          return (id: request.identifier, fireDate: fireDate)
        }
        .sorted { a, b in
          guard let aDate = a.fireDate else { return false }
          guard let bDate = b.fireDate else { return true }
          return aDate < bDate
        }

      if let userId {
        workPatternResult = WorkPatternAnalyzer.analyzeDetailed(for: userId)
      }
    }

    private func notificationLabel(for identifier: String)
      -> (text: String, icon: String, color: Color)
    {
      if identifier.hasPrefix("smart-test-morning") {
        return ("Test morning", "sun.max", .orange)
      }
      if identifier.hasPrefix("smart-test-evening") {
        return ("Test evening", "moon", .purple)
      }
      if identifier.hasPrefix("smart-morning-") {
        let date = String(identifier.dropFirst("smart-morning-".count))
        return ("Morning \(date)", "sun.max", .yellow)
      }
      if identifier.hasPrefix("smart-evening-") {
        let date = String(identifier.dropFirst("smart-evening-".count))
        return ("Evening \(date)", "moon", .indigo)
      }
      if identifier.hasPrefix("shift-reminder-") {
        return ("Reminder", "bell.fill", .blue)
      }
      return (identifier, "questionmark.circle", .secondary)
    }

    // MARK: - Sync Status Section

    private var syncStatusSection: some View {
      // swiftlint:disable:next closure_body_length
      Section("Sync Status") {
        HStack {
          Text("Status")
          Spacer()
          if syncCoordinator.isSyncing {
            HStack(spacing: Spacing.xs) {
              ProgressView()
                .progressViewStyle(.circular)
              Text("Syncing...")
                .foregroundColor(.secondary)
            }
          } else {
            Text("Idle")
              .foregroundColor(.green)
          }
        }

        HStack {
          Text("Last Run")
          Spacer()
          if let lastAttempt = syncCoordinator.lastSyncAttemptedAt {
            Text(lastAttempt, style: .relative)
              .foregroundColor(.secondary)
          } else {
            Text("Never")
              .foregroundColor(.orange)
          }
        }

        HStack {
          Text("Last Successful Sync")
          Spacer()
          if let lastSync = syncCoordinator.lastSyncedAt {
            Text(lastSync, style: .relative)
              .foregroundColor(.secondary)
          } else {
            Text("Never")
              .foregroundColor(.orange)
          }
        }

        HStack {
          Text("Conflicts")
          Spacer()
          if syncCoordinator.conflictCount > 0 {
            Text("\(syncCoordinator.conflictCount)")
              .foregroundColor(.red)
              .bold()
          } else {
            Text("0")
              .foregroundColor(.green)
          }
        }

        if let error = syncCoordinator.lastError {
          HStack {
            Text("Last Error")
            Spacer()
            Text(error)
              .foregroundColor(.red)
              .font(.caption)
              .lineLimit(2)
          }
        }
      }
    }

    // MARK: - State Summary Section

    private var stateSummarySection: some View {
      Section {
        if isLoadingSummary {
          HStack {
            ProgressView()
            Text("Loading summary...")
              .foregroundColor(.secondary)
          }
        } else if let summary = syncStateSummary {
          // Sync State
          Group {
            summaryRow(
              "User Shifts",
              total: summary.shiftCount.total,
              clean: summary.shiftCount.clean,
              dirty: summary.shiftCount.dirty,
              conflict: summary.shiftCount.conflict
            )

            summaryRow(
              "Recurring Shifts",
              total: summary.recurringShiftCount.total,
              clean: summary.recurringShiftCount.clean,
              dirty: summary.recurringShiftCount.dirty,
              conflict: summary.recurringShiftCount.conflict
            )

            summaryRow(
              "Wage Snapshots",
              total: summary.wageSnapshotCount.total,
              clean: summary.wageSnapshotCount.clean,
              dirty: summary.wageSnapshotCount.dirty,
              conflict: summary.wageSnapshotCount.conflict
            )

            HStack {
              Text("User Settings")
              Spacer()
              statusBadge(for: summary.settingsStatus)
            }
          }

          // Updated-at cursors (primary sync cursors)
          if let state = summary.syncState {
            Divider()
            Text("Sync Cursors (updated_at)")
              .font(.caption.bold())
              .foregroundColor(.secondary)
              .padding(.top, Spacing.xxs)

            updatedAtCursorRow("Shifts", cursor: state.updatedAtCursor(for: .userShifts))
            updatedAtCursorRow("Recurring", cursor: state.updatedAtCursor(for: .recurringShifts))
            updatedAtCursorRow("Snapshots", cursor: state.updatedAtCursor(for: .wageSnapshots))
            updatedAtCursorRow("Settings", cursor: state.updatedAtCursor(for: .userSettings))

            // Legacy revision cursors (for debugging only)
            Divider()
            Text("Legacy Revisions (debug)")
              .font(.caption.bold())
              .foregroundColor(.secondary)
              .padding(.top, Spacing.xxs)
            revisionCursorRow("Shifts Rev", revision: state.lastRevisionUserShifts)
            revisionCursorRow("Recurring Rev", revision: state.lastRevisionRecurringShifts)
            revisionCursorRow("Snapshots Rev", revision: state.lastRevisionWageSnapshots)
            revisionCursorRow("Settings Rev", revision: state.lastRevisionUserSettings)
          }
        } else {
          Text("No data loaded")
            .foregroundColor(.secondary)
        }
      } header: {
        HStack {
          Text("Local State Summary")
          Spacer()
          Button {
            Task { await loadSummary() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
        }
      }
    }

    private func summaryRow(_ label: String, total: Int, clean: Int, dirty: Int, conflict: Int)
      -> some View
    {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack {
          Text(label)
          Spacer()
          Text("\(total)")
            .foregroundColor(.secondary)
        }
        HStack(spacing: Spacing.sm) {
          Label("\(clean)", systemImage: "checkmark.circle")
            .foregroundColor(.green)
            .font(.caption)
          Label("\(dirty)", systemImage: "pencil.circle")
            .foregroundColor(.orange)
            .font(.caption)
          Label("\(conflict)", systemImage: "exclamationmark.triangle")
            .foregroundColor(.red)
            .font(.caption)
        }
      }
    }

    private func revisionCursorRow(_ label: String, revision: Int64) -> some View {
      HStack {
        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Text("\(revision)")
          .font(.caption.monospaced())
          .foregroundColor(.secondary)
      }
    }

    private func updatedAtCursorRow(_ label: String, cursor: SyncCursor) -> some View {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        HStack {
          Text(label)
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          if cursor.isInitial {
            Text("(initial)")
              .font(.caption.monospaced())
              .foregroundColor(.orange)
          } else if let date = cursor.updatedAt {
            Text(date, style: .relative)
              .font(.caption.monospaced())
              .foregroundColor(.green)
          }
        }
        if !cursor.isInitial, !cursor.tieId.isEmpty {
          Text("tieId: \(cursor.tieId.prefix(8))...")
            .font(.caption2.monospaced())
            .foregroundColor(.secondary)
        }
      }
    }

    private func statusBadge(for status: SyncStatus) -> some View {
      HStack(spacing: Spacing.xxs) {
        switch status {
        case .clean:
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
          Text("Clean")
            .foregroundColor(.green)

        case .dirty:
          Image(systemName: "pencil.circle.fill")
            .foregroundColor(.orange)
          Text("Dirty")
            .foregroundColor(.orange)

        case .pendingDelete:
          Image(systemName: "trash.circle.fill")
            .foregroundColor(.red)
          Text("Pending Delete")
            .foregroundColor(.red)

        case .conflict:
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red)
          Text("Conflict")
            .foregroundColor(.red)
        }
      }
      .font(.caption)
    }

    // MARK: - Validation Section

    private var validationSection: some View {
      Section {
        if isRunningValidation {
          HStack {
            ProgressView()
            Text("Running validation tests...")
              .foregroundColor(.secondary)
          }
        } else if !validationResults.isEmpty {
          ForEach(validationResults) { result in
            VStack(alignment: .leading, spacing: Spacing.xs) {
              HStack {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                  .foregroundColor(result.passed ? .green : .red)
                Text(result.testName)
                  .font(.subheadline.bold())
              }

              Text(result.details)
                .font(.caption)
                .foregroundColor(.secondary)

              if !result.issues.isEmpty {
                ForEach(result.issues, id: \.self) { issue in
                  HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle")
                      .foregroundColor(.orange)
                      .font(.caption)
                    Text(issue)
                      .font(.caption)
                      .foregroundColor(.orange)
                  }
                }
              }
            }
            .padding(.vertical, Spacing.xxs)
          }
        } else {
          Text("No validation tests run yet")
            .foregroundColor(.secondary)
        }

        Button {
          Task { await runValidation() }
        } label: {
          Label("Run All Validations", systemImage: "checkmark.shield")
        }
        .disabled(isRunningValidation || userId == nil)
      } header: {
        Text("Validation Tests")
      } footer: {
        Text("Tests verify offline sync functionality according to Phase 8 test plan.")
      }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
      Section {
        if testHelper.testLogs.isEmpty {
          Text("No logs yet")
            .foregroundColor(.secondary)
        } else {
          ForEach(testHelper.testLogs.suffix(20).reversed()) { entry in
            VStack(alignment: .leading, spacing: Spacing.micro) {
              HStack {
                Text(entry.formattedTimestamp)
                  .font(.caption2.monospaced())
                  .foregroundColor(.secondary)
                Text("[\(entry.category.rawValue)]")
                  .font(.caption2.bold())
                  .foregroundColor(colorForCategory(entry.category))
              }
              Text(entry.message)
                .font(.caption)
              if let details = entry.details {
                Text(details)
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
            .padding(.vertical, Spacing.micro)
          }
        }

        Button {
          testHelper.clearLogs()
        } label: {
          Label("Clear Logs", systemImage: "trash")
        }
        .foregroundColor(.red)
      } header: {
        Text("Recent Logs (\(testHelper.testLogs.count))")
      }
    }

    private func colorForCategory(_ category: SyncTestHelper.TestLogEntry.LogCategory) -> Color {
      switch category {
      case .sync: return .blue
      case .pull: return .cyan
      case .push: return .indigo
      case .conflict: return .red
      case .merge: return .orange
      case .validation: return .purple
      case .error: return .red
      }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
      Section("Quick Actions") {
        Button {
          Task { await triggerManualSync() }
        } label: {
          Label("Trigger Manual Sync", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(syncCoordinator.isSyncing || userId == nil)
      }
    }

    private var advancedSection: some View {
      Section("Advanced") {
        Toggle(isOn: $showAdvancedSync) {
          Label("Show Sync Diagnostics", systemImage: "wrench.and.screwdriver")
        }

        Button {
          Task { await reloadDebugData() }
        } label: {
          Label("Reload Debug Data", systemImage: "arrow.clockwise")
        }
      }
    }

    private var dangerZoneSection: some View {
      Section("Danger Zone") {
        Button(role: .destructive) {
          showResetLocalDataConfirmation = true
        } label: {
          Label("Reset Local Data", systemImage: "trash")
        }
      }
    }

    // MARK: - Helper Methods

    private func loadUserId() async {
      do {
        userId = try await AuthSessionManager.shared.getUserId()
        await reloadDebugData()
      } catch {
        logger.error("Failed to get user ID: \(error.localizedDescription)")
      }
    }

    private func reloadDebugData() async {
      await loadSummary()
      await loadNotificationState()
    }

    private func loadSummary() async {  // swiftlint:disable:this async_without_await
      guard let userId else { return }

      isLoadingSummary = true
      syncStateSummary = testHelper.getSyncStateSummary(userId: userId)
      isLoadingSummary = false
    }

    private func runValidation() async {
      guard let userId else { return }

      isRunningValidation = true
      validationResults = await testHelper.runAllValidations(userId: userId)
      isRunningValidation = false
    }

    private func triggerManualSync() async {
      guard let userId else { return }

      testHelper.logSyncStart(reason: .manualRefresh, userId: userId)
      let result = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
      testHelper.logSyncComplete(result: result)

      await reloadDebugData()
    }

    private func resetLocalData() async {
      await LocalStore.shared.resetAllData()
      testHelper.log(.validation, "Local data reset")
      syncStateSummary = nil
      validationResults = []
      pendingSmartCount = 0
      pendingReminderCount = 0
      scheduledNotifications = []
      workPatternResult = nil
      testNotificationResult = nil
    }
  }

  // MARK: - Preview

  #Preview {
    NavigationStack {
      SyncDebugView()
    }
  }
#endif
