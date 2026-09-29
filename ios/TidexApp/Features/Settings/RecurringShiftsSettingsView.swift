import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "SettingsView")

struct RecurringShiftsSettingsView: View {
  @State private var recurringShifts: [RecurringShiftRow] = []
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    List {
      Group {
        if let errorMessage {
          Section {
            Label {
              Text(errorMessage)
                .foregroundColor(.tidexError)
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.tidexError)
            }
            .font(.tidexSubheadline)
            .announcesToVoiceOver(errorMessage)
          }
        }

        if isLoading && recurringShifts.isEmpty {
          Section {
            ProgressView()
              .frame(maxWidth: .infinity)
          }
        } else if !recurringShifts.isEmpty {
          Section {
            ForEach(recurringShifts, id: \.id) { recurring in
              recurringShiftRow(recurring)
            }
          } footer: {
            Text(.settingsRecurringShiftsSubtitle)
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .overlay {
      if !isLoading, recurringShifts.isEmpty, errorMessage == nil {
        ContentUnavailableView {
          Label(String(localized: .settingsRecurringShiftsEmptyTitle), systemImage: "repeat")
        } description: {
          Text(.settingsRecurringShiftsEmptyDescription)
        }
      }
    }
    .navigationTitle(String(localized: .settingsRecurringShiftsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadRecurringShifts()
    }
    .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
      Task {
        await loadRecurringShifts()
      }
    }
    .sheet(item: $recurringShiftToEdit) { recurring in
      RecurringShiftEditorSheet(
        recurringShift: recurring,
        onSave: { editResult in
          recurringShiftToEdit = nil
          Task {
            await updateRecurringShift(editResult)
          }
        },
        onDelete: {
          let recurringId = recurring.id
          recurringShiftToEdit = nil
          Task {
            await deleteRecurringShift(recurringId)
          }
        }
      )
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .sensoryFeedback(.impact(weight: .light), trigger: recurringShiftToEdit) { _, new in
      new != nil
    }
  }

  private func recurringShiftRow(_ recurring: RecurringShiftRow) -> some View {
    let exclusionCount = recurring.effectiveExclusions.count
    var details = [
      weekdaySummary(for: recurring.selected_days),
      repeatLabel(for: recurring.repeat_interval_weeks),
    ]
    if exclusionCount > 0 {
      details.append(String(localized: .settingsRecurringShiftsExcludedCount(exclusionCount)))
    }

    let timeRange = String(
      localized: .calendarAccessibilityTimeRange(recurring.cleanStartTime, recurring.cleanEndTime))

    return Button {
      recurringShiftToEdit = recurring
    } label: {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(verbatim: "\(recurring.cleanStartTime) - \(recurring.cleanEndTime)")
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .monospacedDigit()

        Text(verbatim: details.joined(separator: " • "))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
      .padding(.vertical, Spacing.xxxs)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: timeRange))
    .accessibilityValue(Text(verbatim: details.joined(separator: ", ")))
    .accessibilityInputLabels([Text(verbatim: timeRange), Text(verbatim: recurring.cleanStartTime)])
  }

  private func loadRecurringShifts() async {
    isLoading = true
    errorMessage = nil

    do {
      let userId = try await resolveRecurringSettingsUserId()
      let shifts = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)
      recurringShifts = sortRecurringShifts(shifts)
    } catch {
      logger.error("Failed to load recurring shifts settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsLoadFailed)
    }

    isLoading = false
  }

  private func resolveRecurringSettingsUserId() async throws -> String {
    do {
      let session = try await AuthSessionManager.shared.getSession()
      return session.normalizedUserId
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback()
      else {
        throw error
      }

      return offlineUserId
    }
  }

  private func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
    do {
      _ = try await RecurringShiftsRepository.shared.updateRecurringShift(
        id: editResult.recurringId,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        repeatIntervalWeeks: editResult.repeatIntervalWeeks,
        selectedDays: editResult.selectedDays,
        endCondition: editResult.endCondition,
        exclusions: editResult.exclusions
      )

      await loadRecurringShifts()
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)
      Haptics.play(.success)
    } catch {
      logger.error("Failed to update recurring shift from settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsSaveFailed)
    }
  }

  private func deleteRecurringShift(_ recurringId: String) async {
    do {
      try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)
      await loadRecurringShifts()
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)
      Haptics.play(.success)
    } catch {
      logger.error("Failed to delete recurring shift from settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsDeleteFailed)
    }
  }

  private func sortRecurringShifts(_ shifts: [RecurringShiftRow]) -> [RecurringShiftRow] {
    shifts.sorted { lhs, rhs in
      let lhsEarliestAnchor = lhs.selected_days.values.min() ?? "9999-12-31"
      let rhsEarliestAnchor = rhs.selected_days.values.min() ?? "9999-12-31"
      if lhsEarliestAnchor != rhsEarliestAnchor {
        return lhsEarliestAnchor < rhsEarliestAnchor
      }
      if lhs.cleanStartTime != rhs.cleanStartTime {
        return lhs.cleanStartTime < rhs.cleanStartTime
      }
      return lhs.id < rhs.id
    }
  }

  private func weekdaySummary(for selectedDays: SelectedDays) -> String {
    let order = ["1", "2", "3", "4", "5", "6", "0"]
    var calendar = Calendar.gregorianCurrent
    calendar.locale = Locale(identifier: Locale.current.identifier)
    let symbols = calendar.shortWeekdaySymbols
    let labels =
      order
      .filter { selectedDays[$0] != nil }
      .compactMap { key -> String? in
        guard let index = Int(key), index >= 0, index < symbols.count else { return nil }
        return symbols[index]
      }
    return labels.joined(separator: ", ")
  }

  private func repeatLabel(for repeatInterval: Int) -> String {
    String(localized: .addShiftEveryNWeeks(repeatInterval + 1))
  }
}
