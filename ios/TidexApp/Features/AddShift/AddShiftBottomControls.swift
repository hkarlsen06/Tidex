import SwiftUI

/// Job picker and Add above, undo and month picker below, pinned to the bottom of the add screen.
struct AddShiftBottomControls: View {
  private static let jobPickerMaxNameWidth: CGFloat = 140

  let viewModel: AddShiftViewModel
  let onStartFresh: () -> Void
  let onSave: () -> Void
  private let addShiftCoordinator = AddShiftCoordinator.shared
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// The job picker and Add button stack at accessibility text sizes so neither is squeezed.
  private var primaryRowLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.xs)) : AnyLayout(HStackLayout(spacing: Spacing.xs))
  }

  var body: some View {
    VStack(spacing: Spacing.xs) {
      primaryRowLayout {
        if viewModel.mode != .events {
          jobPickerButton
        }
        saveButton
      }

      HStack(spacing: Spacing.xs) {
        startFreshButton

        SharedMonthPicker()
          .frame(maxWidth: .infinity)
          .frame(minHeight: MonthPickerLayout.height)
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

        Text(jobPickerTitle)
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
          .truncationMode(.tail)
          .frame(
            maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : Self.jobPickerMaxNameWidth,
            alignment: .leading
          )
          .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)

        Image(systemName: "chevron.up.chevron.down")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextSecondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, Spacing.md)
      .frame(minHeight: MonthPickerLayout.height)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityLabel(Text(verbatim: jobPickerTitle))
    .accessibilityHint(Text(.shiftsAccessibilityChangeJobHint))
    .accessibilityIdentifier("add-shift.job-picker")
  }

  private var jobPickerTitle: String {
    viewModel.selectedJob?.name ?? String(localized: .settingsPayChooseJobTitle)
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
        .frame(minWidth: MonthPickerLayout.height, minHeight: MonthPickerLayout.height)
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

  private var saveButtonHint: Text {
    guard !addShiftCoordinator.canSubmit else { return Text(verbatim: "") }
    let message: LocalizedStringResource =
      addShiftCoordinator.submitBlockers.first?.requirementMessage
      ?? .addShiftSubmitRequirementsGeneric
    return Text(message)
  }

  private var saveButton: some View {
    Button {
      onSave()
    } label: {
      Label(String(localized: .addShiftSubmitButton), systemImage: "plus")
        .font(.tidexButton)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .foregroundColor(addShiftCoordinator.canSubmit ? .tidexBlueText : .tidexTextMuted)
        // Keep the width while saving so the month picker doesn't jump.
        .opacity(addShiftCoordinator.isLoading ? 0 : 1)
        .overlay {
          if addShiftCoordinator.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
              .scaleEffect(MonthPickerLayout.progressIndicatorScale)
          }
        }
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity)
        .frame(minHeight: MonthPickerLayout.height)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(addShiftCoordinator.isLoading)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    // The button stays active when it can't submit, so it explains what is missing instead.
    .accessibilityHint(saveButtonHint)
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
