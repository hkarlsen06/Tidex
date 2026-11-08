import SwiftUI

struct ClockOutReviewSheet: View {
  let loadJobs: () async -> [Job]
  let jobRequiringPaySetup: (String?) async -> Job?
  let onPaySetupRequired: (Date, Date, String?, Job) -> Void
  let onSave: (Date, Date, String?) async throws -> Void
  let onDiscard: () async -> Void

  @Environment(\.dismiss) private var dismiss  // swiftlint:disable:this explicit_type_interface
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface
  @State private var availableJobs: [Job]
  @State private var startTime: Date?
  @State private var endTime: Date?
  @State private var selectedJobId: String?
  @State private var focusedTimeField: TimeInputField?
  @State private var showJobChooser = false  // swiftlint:disable:this explicit_type_interface
  @State private var isSaving = false  // swiftlint:disable:this explicit_type_interface
  @State private var isDiscarding = false  // swiftlint:disable:this explicit_type_interface
  @State private var errorMessage: String?

  init(  // swiftlint:disable:this type_contents_order
    session: TemporaryClockSession,
    initialAvailableJobs: [Job],
    loadJobs: @escaping () async -> [Job],
    initialSelectedJobId: String?,
    jobRequiringPaySetup: @escaping (String?) async -> Job?,
    onPaySetupRequired: @escaping (Date, Date, String?, Job) -> Void,
    onSave: @escaping (Date, Date, String?) async throws -> Void,
    onDiscard: @escaping () async -> Void
  ) {
    self.loadJobs = loadJobs
    self.jobRequiringPaySetup = jobRequiringPaySetup
    self.onPaySetupRequired = onPaySetupRequired
    self.onSave = onSave
    self.onDiscard = onDiscard

    let initialStart = session.startedAt  // swiftlint:disable:this explicit_type_interface
    let initialEnd = max(Date(), initialStart.addingTimeInterval(60))  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    let fallbackJobId =  // swiftlint:disable:this explicit_type_interface
      initialSelectedJobId
      ?? initialAvailableJobs.first(where: \.is_default)?.id
      ?? initialAvailableJobs.first?.id
    _availableJobs = State(initialValue: initialAvailableJobs)
    _startTime = State(initialValue: initialStart)
    _endTime = State(initialValue: initialEnd)
    _selectedJobId = State(initialValue: fallbackJobId)
  }

  private var selectedJob: Job? {
    guard let selectedJobId else {
      return availableJobs.first
    }
    return availableJobs.first(where: { $0.id == selectedJobId }) ?? availableJobs.first
  }

  private var resolvedEndTime: Date? {
    guard let startTime, let endTime else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    guard endTime <= startTime else { return endTime }  // swiftlint:disable:this conditional_returns_on_newline
    return Calendar.gregorianCurrent.date(byAdding: .day, value: 1, to: endTime) ?? endTime
  }

  private var isValidRange: Bool {
    guard let startTime, let resolvedEndTime else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return resolvedEndTime > startTime
  }

  private var showsCrossMidnightHint: Bool {
    guard let startTime, let resolvedEndTime else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return !Calendar.gregorianCurrent.isDate(startTime, inSameDayAs: resolvedEndTime)
  }

  private var isWorking: Bool {
    isSaving || isDiscarding
  }

  private var durationText: String {
    guard isValidRange, let startTime, let resolvedEndTime else { return "--" }  // swiftlint:disable:this conditional_returns_on_newline line_length
    // swiftlint:disable:next explicit_type_interface no_magic_numbers
    let wholeMinutes = Duration.seconds(Int(resolvedEndTime.timeIntervalSince(startTime) / 60) * 60)
    return wholeMinutes.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }

  var body: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      ScrollView {  // swiftlint:disable:this closure_body_length
        VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
          VStack(spacing: Spacing.xxs) {
            Text(durationText)
              .font(.tidexAmountLarge)
              .monospacedDigit()
              .foregroundStyle(isValidRange ? Color.tidexTextPrimary : Color.tidexTextMuted)
              .contentTransition(reduceMotion ? .identity : .numericText())
              .animation(reduceMotion ? nil : .snappy, value: durationText)
            if let startTime {
              Text(startTime, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.tidexSubheadline)
                .foregroundStyle(Color.tidexTextSecondary)
            }
          }
          .frame(maxWidth: .infinity)
          .accessibilityElement(children: .combine)

          VStack(spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
            TimeRangePicker(
              startTime: $startTime,
              endTime: $endTime,
              focusedFieldBinding: $focusedTimeField,
              showsRecentTimeChips: false
            )

            if availableJobs.count > 1 {
              Divider()

              Button {
                showJobChooser = true
              } label: {
                HStack(spacing: Spacing.sm) {
                  Text(.settingsPayChooseJobTitle)
                    .font(.tidexSubheadline)
                    .foregroundStyle(Color.tidexTextSecondary)

                  Spacer(minLength: Spacing.sm)

                  if let selectedJob {
                    WorkplaceNameText(
                      name: selectedJob.name,
                      colorHex: selectedJob.color,
                      font: .tidexMonoCaption,
                      fallbackBadgeColor: .tidexBlue,
                      lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 1,
                      badgeHorizontalPadding: Spacing.xs,
                      badgeVerticalPadding: 2  // swiftlint:disable:this no_magic_numbers
                    )
                    .truncationMode(.tail)
                  }

                  Image(systemName: "chevron.up.chevron.down")
                    .font(.tidexMicro)
                    .foregroundStyle(Color.tidexTextMuted)
                    .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          .padding(Spacing.md)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
              .fill(Color.tidexSurfacePrimary)
          )

          if showsCrossMidnightHint {
            HStack(spacing: Spacing.xs) {
              Image(systemName: "moon.fill")
                .font(.tidexCaption)
                .foregroundStyle(Color.tidexTextSecondary)
                .accessibilityHidden(true)
              Text(.shiftsCrossMidnightInfo)
                .font(.tidexFootnote)
                .foregroundStyle(Color.tidexTextSecondary)
            }
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.tidexFootnote)
              .foregroundStyle(Color.tidexError)
              .announcesToVoiceOver(errorMessage)
          }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
      }
      .background(Color.tidexBackground.ignoresSafeArea())
      .navigationTitle(.dashboardClockOutReviewTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .disabled(isWorking)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonSave)) {
            Task {
              await save()
            }
          }
          .disabled(isWorking || !isValidRange)
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button(role: .destructive) {
          Task {
            await discard()
          }
        } label: {
          Label(String(localized: .dashboardClockOutDiscardShift), systemImage: "trash")
            .font(.tidexLabel)
            .foregroundStyle(Color.tidexError)
            .frame(maxWidth: .infinity, minHeight: 44)  // swiftlint:disable:this no_magic_numbers
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
        .disabled(isWorking)
      }
      .task {
        await ensureJobsLoaded()
      }
      .sheet(isPresented: $showJobChooser) {
        JobChooserSheet(
          jobs: availableJobs,
          selectedJobId: selectedJobId,
          onSelect: { jobId in
            selectedJobId = jobId
            showJobChooser = false
          },
          onCancel: {
            showJobChooser = false
          }
        )
      }
    }
  }

  private func save() async {
    guard !isSaving else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard isValidRange else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard let startTime, let resolvedEndTime else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isSaving = true
    errorMessage = nil

    do {
      if let job = await jobRequiringPaySetup(selectedJobId) {
        onPaySetupRequired(startTime, resolvedEndTime, selectedJobId, job)
        isSaving = false
        dismiss()
        return
      }

      try await onSave(startTime, resolvedEndTime, selectedJobId)
      dismiss()
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }

    isSaving = false
  }

  private func discard() async {
    guard !isWorking else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isDiscarding = true
    await onDiscard()
    isDiscarding = false
    dismiss()
  }

  private func ensureJobsLoaded() async {
    guard availableJobs.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline
    let loadedJobs = await loadJobs()  // swiftlint:disable:this explicit_type_interface
    guard !loadedJobs.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline
    availableJobs = loadedJobs
    if selectedJobId == nil {
      selectedJobId = loadedJobs.first(where: \.is_default)?.id ?? loadedJobs.first?.id
    }
  }
}