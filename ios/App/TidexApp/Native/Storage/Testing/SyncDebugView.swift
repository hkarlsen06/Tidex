import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SyncDebugView")

// MARK: - Sync Debug View

/// Debug view for testing and validating offline sync functionality
/// Accessible from Settings > Debug > Sync Debug (only in debug builds)
struct SyncDebugView: View {
    @StateObject private var testHelper = SyncTestHelper.shared
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared

    @State private var userId: String?
    @State private var syncStateSummary: SyncStateSummary?
    @State private var validationResults: [ValidationResult] = []
    @State private var isRunningValidation = false
    @State private var isLoadingSummary = false

    var body: some View {
        List {
            // Sync Status Section
            syncStatusSection

            // State Summary Section
            stateSummarySection

            // Validation Tests Section
            validationSection

            // Logs Section
            logsSection

            // Actions Section
            actionsSection
        }
        .navigationTitle("Sync Debug")
        .task {
            await loadUserId()
        }
        .refreshable {
            await loadSummary()
        }
    }

    // MARK: - Sync Status Section

    private var syncStatusSection: some View {
        Section("Sync Status") {
            HStack {
                Text("Status")
                Spacer()
                if syncCoordinator.isSyncing {
                    HStack(spacing: 8) {
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
                Text("Last Synced")
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
                        .padding(.top, 4)

                    updatedAtCursorRow("Shifts", cursor: state.updatedAtCursor(for: .userShifts))
                    updatedAtCursorRow("Recurring", cursor: state.updatedAtCursor(for: .recurringShifts))
                    updatedAtCursorRow("Snapshots", cursor: state.updatedAtCursor(for: .wageSnapshots))
                    updatedAtCursorRow("Settings", cursor: state.updatedAtCursor(for: .userSettings))

                    // Legacy revision cursors (for debugging only)
                    Divider()
                    Text("Legacy Revisions (debug)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
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

    private func summaryRow(_ label: String, total: Int, clean: Int, dirty: Int, conflict: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(total)")
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 2) {
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
        HStack(spacing: 4) {
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
                    VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.vertical, 4)
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
                    VStack(alignment: .leading, spacing: 2) {
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
                    .padding(.vertical, 2)
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

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                Task { await triggerManualSync() }
            } label: {
                Label("Trigger Manual Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(syncCoordinator.isSyncing || userId == nil)

            Button {
                Task { await resetLocalData() }
            } label: {
                Label("Reset Local Data", systemImage: "trash")
            }
            .foregroundColor(.red)
        }
    }

    // MARK: - Helper Methods

    private func loadUserId() async {
        do {
            let session = try await supabase.auth.session
            userId = session.user.id.uuidString.lowercased()
            await loadSummary()
        } catch {
            logger.error("Failed to get user ID: \(error.localizedDescription)")
        }
    }

    private func loadSummary() async {
        guard let userId = userId else { return }

        isLoadingSummary = true
        syncStateSummary = await testHelper.getSyncStateSummary(userId: userId)
        isLoadingSummary = false
    }

    private func runValidation() async {
        guard let userId = userId else { return }

        isRunningValidation = true
        validationResults = await testHelper.runAllValidations(userId: userId)
        isRunningValidation = false
    }

    private func triggerManualSync() async {
        guard let userId = userId else { return }

        testHelper.logSyncStart(reason: .manualRefresh, userId: userId)
        let result = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
        testHelper.logSyncComplete(result: result)

        await loadSummary()
    }

    private func resetLocalData() async {
        await LocalStore.shared.resetAllData()
        testHelper.log(.validation, "Local data reset")
        syncStateSummary = nil
        validationResults = []
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SyncDebugView()
    }
}
