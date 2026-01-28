import SwiftUI

// MARK: - Pay Settings View

/// Main pay settings screen displaying wage history timeline and global settings
struct PaySettingsView: View {
    @StateObject private var viewModel = PaySettingsViewModel()
    @Environment(\.localization) private var localization

    var body: some View {
        ZStack {
            Color.tidexBackground
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.snapshots.isEmpty {
                // Initial loading state
                loadingView
            } else {
                // Main content
                mainContent
            }
        }
        .navigationTitle(localization.string("settings.pay.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
        .sheet(isPresented: $viewModel.showingEditor) {
            WageSnapshotEditorSheet(
                mode: viewModel.editorMode,
                snapshot: viewModel.selectedSnapshot,
                mostRecentSnapshot: viewModel.snapshots.first,
                userCurrency: viewModel.userCurrency,
                onSave: { input in
                    if viewModel.editorMode == .create {
                        return await viewModel.createSnapshot(input: input)
                    } else if let snapshot = viewModel.selectedSnapshot {
                        return await viewModel.updateSnapshot(id: snapshot.id, input: input)
                    }
                    return false
                },
                onDelete: { snapshot in
                    viewModel.requestDelete(snapshot: snapshot)
                },
                onCancel: {
                    viewModel.closeEditor()
                }
            )
        }
        .confirmationDialog(
            localization.string("settings.pay.deleteConfirmTitle"),
            isPresented: $viewModel.showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await viewModel.confirmDelete() }
            } label: {
                Text(localization.string("common.delete"))
            }

            Button(role: .cancel) {
                viewModel.cancelDelete()
            } label: {
                Text(localization.string("common.cancel"))
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert(
            localization.string("common.error"),
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearMessages() } }
            )
        ) {
            Button(localization.string("common.ok")) {
                viewModel.clearMessages()
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBrandPrimary))

            Text(localization.string("common.loading"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Wage History Timeline
                WageHistoryTimelineView(
                    entries: viewModel.timelineEntries,
                    onAddNew: { viewModel.openCreateEditor() },
                    onEdit: { snapshot in viewModel.openEditEditor(snapshot: snapshot) }
                )
                .padding(.horizontal, 16)

                // Tip box
                tipBox
                    .padding(.horizontal, 16)

                // Divider
                Divider()
                    .padding(.horizontal, 32)

                // Global Pay Settings
                GlobalPaySettingsCard(
                    settings: viewModel.globalSettings,
                    canChangeCurrency: viewModel.canChangeCurrency,
                    onUpdateMonthlyGoal: { viewModel.updateMonthlyGoal($0) },
                    onUpdatePayrollDay: { viewModel.updatePayrollDay($0) },
                    onUpdateHalfTaxMonth: { value in
                        await viewModel.updateHalfTaxMonth(value)
                    },
                    onUpdateCurrency: { value in
                        await viewModel.updateCurrency(value)
                    }
                )
                .padding(.horizontal, 16)

                // Bottom padding
                Spacer()
                    .frame(height: 40)
            }
            .padding(.vertical, 24)
        }
        .refreshable {
            await viewModel.loadData()
        }
    }

    // MARK: - Tip Box

    private var tipText: AttributedString {
        let tipLabel = localization.string("settings.pay.timeline.tipLabel")
        let infoTip = localization.string("settings.pay.timeline.infoTip")

        var result = AttributedString("\(tipLabel) \(infoTip)")

        // Make the tip label bold
        if let range = result.range(of: tipLabel) {
            result[range].font = .system(size: 14, weight: .semibold)
        }

        return result
    }

    @ViewBuilder
    private var tipBox: some View {
        Text(tipText)
            .font(.system(size: 14))
            .foregroundColor(.tidexBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.tidexBlue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(localization.string("settings.pay.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("settings.pay.subtitle"))
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Delete Confirmation Message

    private var deleteConfirmationMessage: String {
        let count = viewModel.affectedShiftCount
        let isNorwegian = localization.currentLocale == .norwegian

        if count == 0 {
            return isNorwegian
                ? "Er du sikker på at du vil slette denne lønnssettingen?"
                : "Are you sure you want to delete this wage setting?"
        } else if count == 1 {
            return isNorwegian
                ? "Dette vil påvirke 1 vakt. Er du sikker på at du vil slette denne lønnssettingen?"
                : "This will affect 1 shift. Are you sure you want to delete this wage setting?"
        } else {
            return isNorwegian
                ? "Dette vil påvirke \(count) vakter. Er du sikker på at du vil slette denne lønnssettingen?"
                : "This will affect \(count) shifts. Are you sure you want to delete this wage setting?"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PaySettingsView()
    }
    .environment(\.localization, LocalizationManager.shared)
}
