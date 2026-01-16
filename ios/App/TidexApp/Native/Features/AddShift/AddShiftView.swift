import SwiftUI
import UIKit

/// Add Shift tab view - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
    @Environment(\.localization) private var localization
    @StateObject private var viewModel = AddShiftViewModel()
    @Binding var selectedTab: MainTabView.Tab

    var body: some View {
        TabScreenContainer(title: localization.string(AppTab.add.titleKey)) {
            ScrollView {
                VStack(spacing: 24) {
                    ShiftModeToggle(mode: $viewModel.mode)

                    switch viewModel.mode {
                    case .single:
                        SingleShiftContent(viewModel: viewModel)
                    case .recurring:
                        RecurringShiftContent(viewModel: viewModel)
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                hideKeyboard()
            }
            .safeAreaInset(edge: .bottom) {
                FixedBottomButton(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.onShiftsCreated = {
                selectedTab = .shifts
            }
        }
        .sheet(isPresented: $viewModel.showPreviewSheet) {
            RecurringPreviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showPaywall) {
            PaywallView(contextType: .monthLimit)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Single Shift Content

private struct SingleShiftContent: View {
    @ObservedObject var viewModel: AddShiftViewModel

    var body: some View {
        VStack(spacing: 24) {
            ShiftCalendarView(viewModel: viewModel)

            TimeRangePicker(
                startTime: $viewModel.startTime,
                endTime: $viewModel.endTime
            )
        }
    }
}

// MARK: - Recurring Shift Content

private struct RecurringShiftContent: View {
    @ObservedObject var viewModel: AddShiftViewModel
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 20) {
            RepeatIntervalPicker(interval: $viewModel.repeatInterval)

            DurationPicker(endCondition: $viewModel.endCondition)

            Divider()
                .background(Color.tidexBorder)

            WeekdayChipBar(
                selectedDays: viewModel.selectedDays,
                onRemove: { weekday in
                    viewModel.removeAnchor(weekday: weekday)
                }
            )

            RecurringCalendarView(viewModel: viewModel)

            TimeRangePicker(
                startTime: $viewModel.startTime,
                endTime: $viewModel.endTime
            )
        }
    }
}

// MARK: - Fixed Bottom Button

private struct FixedBottomButton: View {
    @ObservedObject var viewModel: AddShiftViewModel
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 0) {
            // Gradient fade
            LinearGradient(
                colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)

            // Button container
            VStack {
                // Error display
                if let error = viewModel.error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.tidexError)

                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.tidexError)
                    }
                    .padding(.bottom, 8)
                }

                // Action button
                Button(action: handleSubmit) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(buttonTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 54)
                .foregroundColor(.white)
                .background(canSubmit ? Color.tidexBlue : Color.tidexTextMuted)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!canSubmit || viewModel.isLoading)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: canSubmit)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(Color.tidexBackground)
        }
    }

    private var canSubmit: Bool {
        switch viewModel.mode {
        case .single:
            return viewModel.canSubmitSingle
        case .recurring:
            return viewModel.canSubmitRecurring
        }
    }

    private var buttonTitle: String {
        switch viewModel.mode {
        case .single:
            let count = viewModel.selectedDates.count
            if count == 0 {
                return localization.string("addShift.selectDates")
            } else if count == 1 {
                return localization.string("addShift.addShift")
            } else {
                return localization.string("addShift.addShifts")
                    .replacingOccurrences(of: "{count}", with: "\(count)")
            }
        case .recurring:
            if viewModel.selectedDays.isEmpty {
                return localization.string("addShift.selectAnchorDates")
            } else {
                return localization.string("addShift.previewShifts")
            }
        }
    }

    private func handleSubmit() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        switch viewModel.mode {
        case .single:
            Task {
                await viewModel.submitSingleShifts()
            }
        case .recurring:
            viewModel.showPreview()
        }
    }
}

// MARK: - Preview

#Preview {
    AddShiftView(selectedTab: .constant(.add))
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
