import SwiftUI

private struct PauseWindowDraft: Identifiable, Equatable {
  let id: UUID
  var startTime: Date?
  var endTime: Date?

  init(id: UUID = UUID(), startTime: Date?, endTime: Date?) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
  }

  init(window: PauseWindow) {
    self.init(
      startTime: Self.date(for: window.start),
      endTime: Self.date(for: window.end)
    )
  }

  func toPauseWindow() -> PauseWindow? {
    guard let startTime, let endTime else { return nil }
    return PauseWindow(
      start: startTime.toHourMinuteString(),
      end: endTime.toHourMinuteString()
    )
  }

  var durationMinutes: Int? {
    guard let startTime, let endTime else { return nil }
    let start = Self.minutes(for: startTime.toHourMinuteString())
    var end = Self.minutes(for: endTime.toHourMinuteString())
    if end <= start {
      end += 24 * 60
    }
    return end - start
  }

  static func date(for time: String) -> Date {
    let components = time.split(separator: ":")
    guard components.count == 2,
      let hour = Int(components[0]),
      let minute = Int(components[1])
    else {
      return Date()
    }

    let calendar = Calendar.gregorianCurrent
    var dateComponents = calendar.dateComponents([.year, .month, .day], from: Date())
    dateComponents.hour = hour == 24 ? 0 : hour
    dateComponents.minute = minute
    return calendar.date(from: dateComponents) ?? Date()
  }

  private static func minutes(for hhmm: String) -> Int {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return 0 }
    return (parts[0] * 60) + parts[1]
  }
}

struct CustomPauseWindowsEditorSheet: View {
  let shift: ShiftWithComputations
  let onSave: (CustomPauseWindows?) -> Void
  let onCancel: () -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var drafts: [PauseWindowDraft] = []
  @State private var hadCustomPauseWindows = false

  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

  private var normalizedDrafts: CustomPauseWindows? {
    let windows = drafts.compactMap { $0.toPauseWindow() }
    guard windows.count == drafts.count else { return nil }
    return PauseWindowSupport.normalize(CustomPauseWindows(windows: windows))
  }

  private var allPauseWindowsWithinShift: Bool {
    guard let normalizedDrafts else { return false }
    return normalizedDrafts.windows.allSatisfy {
      PauseWindowSupport.isWithinShift(
        $0,
        shiftStartTime: shift.startTime,
        shiftEndTime: shift.endTime
      )
    }
  }

  private var canSave: Bool {
    if drafts.isEmpty {
      return hadCustomPauseWindows
    }

    guard let normalizedDrafts else { return false }
    return normalizedDrafts.windows.count == drafts.count && allPauseWindowsWithinShift
  }

  private var validationMessage: String? {
    guard !drafts.isEmpty else { return nil }
    guard drafts.allSatisfy({ $0.startTime != nil && $0.endTime != nil }) else {
      return String(localized: .addShiftSubmitRequirementsSetTimes)
    }
    guard let normalizedDrafts else {
      return String(localized: .shiftsPauseEditorValidationDifferentTime)
    }
    guard normalizedDrafts.windows.count == drafts.count else {
      return String(localized: .shiftsPauseEditorValidationUniqueWindows)
    }
    guard allPauseWindowsWithinShift else {
      return String(localized: .shiftsPauseEditorValidationWithinShift)
    }
    return nil
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.mlg) {
          if drafts.isEmpty {
            emptyState
          } else {
            draftsList
          }

          addButton

          if let validationMessage {
            Text(validationMessage)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          Spacer()
            .frame(height: 80)
        }
        .padding(Spacing.mlg)
      }
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .settingsPayEditorBreakTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            onCancel()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonSave)) {
            saveChanges()
          }
          .fontWeight(.semibold)
          .disabled(!canSave)
        }
      }
      .onAppear {
        initializeDrafts()
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "pause.circle")
        .font(.system(size: 28))
        .foregroundColor(.tidexTextMuted)

      Text(.shiftsPauseEditorEmptyState)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(Spacing.xl)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
  }

  private var draftsList: some View {
    VStack(spacing: Spacing.md) {
      ForEach($drafts) { $draft in
        VStack(spacing: Spacing.md) {
          HStack {
            Spacer()
            Button(role: .destructive) {
              deleteDraft(id: draft.id)
            } label: {
              Image(systemName: "trash")
                .font(.tidexFootnote)
            }
            .buttonStyle(.plain)
            .foregroundColor(.tidexError)
          }

          PauseWindowTimeInputs(
            startTime: $draft.startTime,
            endTime: $draft.endTime
          )

          HStack {
            Text(.shiftsPauseEditorDurationLabel)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)

            Spacer()

            Group {
              if let durationMinutes = draft.durationMinutes {
                Text("\(durationMinutes) \(String(localized: .commonMinutesShort))")
              } else {
                Text("—")
              }
            }
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          }
        }
        .padding(Spacing.md)
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      }
    }
  }

  private var addButton: some View {
    Button {
      impactHaptic.impactOccurred()
      drafts.append(defaultDraft())
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "plus")
          .foregroundColor(.tidexTextPrimary)
        Text(.shiftsPauseEditorAddWindow)
          .foregroundColor(.tidexBlue)
      }
      .font(.tidexLabelStrong)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.md)
      .background(Color.tidexBlue.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func initializeDrafts() {
    let normalized = PauseWindowSupport.normalize(shift.shift.custom_pause_windows)
    hadCustomPauseWindows = normalized != nil
    drafts = normalized?.windows.map(PauseWindowDraft.init(window:)) ?? []
  }

  private func defaultDraft() -> PauseWindowDraft {
    let calendar = Calendar.gregorianCurrent
    let start =
      PauseWindowDraft.date(
        for: shift.startTime.count >= 5 ? String(shift.startTime.prefix(5)) : "12:00")
    let end = calendar.date(byAdding: .minute, value: 30, to: start) ?? start
    return PauseWindowDraft(startTime: start, endTime: end)
  }

  private func deleteDraft(id: UUID) {
    drafts.removeAll { $0.id == id }
  }

  private func saveChanges() {
    guard canSave else { return }
    impactHaptic.impactOccurred()
    onSave(normalizedDrafts)
    dismiss()
  }
}

private struct PauseWindowTimeInputs: View {
  @Binding var startTime: Date?
  @Binding var endTime: Date?

  @State private var focusController = TimeInputFocusController()

  private var startLabel: String {
    String(localized: .commonStart)
  }

  private var endLabel: String {
    String(localized: .commonEnd)
  }

  var body: some View {
    HStack(spacing: Spacing.sm) {
      NumericTimeInput(
        time: $startTime,
        label: startLabel,
        focusController: focusController,
        field: .start,
        nextField: .end,
        previousField: nil,
        onComplete: nil
      )

      NumericTimeInput(
        time: $endTime,
        label: endLabel,
        focusController: focusController,
        field: .end,
        nextField: nil,
        previousField: .start,
        onComplete: nil
      )
    }
  }
}
