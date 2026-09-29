import SwiftUI

/// Job picker and Add above, undo and month picker below, pinned to the bottom of the add screen.
struct AddShiftBottomControls: View {
  private static let jobPickerMaxNameWidth: CGFloat = 140

  let viewModel: AddShiftViewModel
  let onStartFresh: () -> Void
  let onSave: () -> Void
  private let addShiftCoordinator = AddShiftCoordinator.shared

  var body: some View {
    VStack(spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        if viewModel.mode != .events {
          jobPickerButton
        }
        saveButton
      }

      HStack(spacing: Spacing.xs) {
        startFreshButton

        SharedMonthPicker()
          .frame(maxWidth: .infinity)
          .frame(height: MonthPickerLayout.height)
          .tidexGlass(
            shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
            interactive: true
          )
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.md)
    .padding(.bottom, MonthPickerLayout.bottomPadding)
  }

  /// Job color dot and name on plain glass, matching the other bottom controls.
  private var jobPickerButton: some View {
    Button {
      viewModel.presentJobSelection()
    } label: {
      HStack(spacing: Spacing.xs) {
        Circle()
          .fill(selectedJobColor)
          .frame(width: Spacing.xsm, height: Spacing.xsm)
          .accessibilityHidden(true)

        Text(viewModel.selectedJob?.name ?? String(localized: .settingsPayChooseJobTitle))
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: Self.jobPickerMaxNameWidth, alignment: .leading)
          .fixedSize(horizontal: true, vertical: false)

        Image(systemName: "chevron.up.chevron.down")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextSecondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, Spacing.md)
      .frame(height: MonthPickerLayout.height)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityIdentifier("add-shift.job-picker")
  }

  private var selectedJobColor: Color {
    guard let job = viewModel.selectedJob,
      let color = WorkplaceColor.hexToUIColor(job.color)
    else {
      return .tidexBlue
    }
    return Color(uiColor: color)
  }

  private var startFreshButton: some View {
    Button {
      Haptics.play(.selection)
      onStartFresh()
    } label: {
      Image(systemName: "arrow.uturn.backward.circle.fill")
        .font(.tidexHeadline)
        .foregroundColor(viewModel.hasContent ? .tidexTextPrimary : .tidexTextMuted)
        .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .disabled(!viewModel.hasContent || addShiftCoordinator.isLoading)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityLabel(Text(.addShiftStartFreshConfirmAction))
  }

  private var saveButton: some View {
    Button {
      onSave()
    } label: {
      Label(String(localized: .addShiftSubmitButton), systemImage: "plus")
        .font(.tidexButton)
        .lineLimit(1)
        .foregroundColor(addShiftCoordinator.canSubmit ? .tidexBlue : .tidexTextMuted)
        // Keep the width while saving so the month picker doesn't jump.
        .opacity(addShiftCoordinator.isLoading ? 0 : 1)
        .overlay {
          if addShiftCoordinator.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
              .scaleEffect(MonthPickerLayout.progressIndicatorScale)
          }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity)
        .frame(height: MonthPickerLayout.height)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(addShiftCoordinator.isLoading)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .opacity(
      addShiftCoordinator.canSubmit
        ? MonthPickerLayout.enabledOpacity
        : MonthPickerLayout.disabledOpacity
    )
    .accessibilityIdentifier("add-shift.save")
  }
}

extension AddShiftSubmitBlocker {
  /// Line shown in the alert that explains why the add button is not ready.
  var requirementMessage: LocalizedStringResource {
    switch self {
    case .noAvailableJob:
      return .addShiftSubmitRequirementsAddJobFirst

    case .noSelectedJob:
      return .addShiftSubmitRequirementsSelectJob

    case .noSingleDates:
      return .addShiftSubmitRequirementsSelectDate

    case .noRecurringDays:
      return .addShiftSubmitRequirementsSelectRecurringDay

    case .missingTimes:
      return .addShiftSubmitRequirementsSetTimes

    case .noEventDate:
      return .addShiftSubmitRequirementsSelectEventDate

    case .invalidEventDateRange:
      return .addShiftSubmitRequirementsValidEventRange

    case .eventCrossesMidnight:
      return .addShiftSubmitRequirementsEventSameDay

    case .missingEventNote:
      return .addShiftSubmitRequirementsEventNote
    }
  }
}
