import Observation
import SwiftUI
import os.log

private let kLogger: Logger = Logger(subsystem: "com.tidex.app", category: "CalendarImport")

/// Downloads an employer calendar feed and saves its shifts through `ShiftsRepository`,
/// so imported shifts get the same pay calculation, sync and validation as manual ones.
@MainActor
@Observable
internal final class CalendarImportModel {
  internal var link: String = ""
  internal private(set) var foundShifts: [CalendarImportShift] = []
  internal private(set) var jobs: [Job] = []
  internal var selectedJobId: String? {
    didSet { refreshExistingShiftKeys() }
  }
  internal private(set) var isWorking: Bool = false
  internal private(set) var errorMessage: String?
  internal private(set) var hasFetched: Bool = false
  private var existingShiftKeys: Set<String> = []

  /// Found shifts that the selected job does not already have (same date, start and end).
  internal var newShifts: [CalendarImportShift] {
    foundShifts.filter { !existingShiftKeys.contains($0.id) }
  }

  internal var duplicateCount: Int {
    foundShifts.count - newShifts.count
  }

  internal func loadJobs() {
    guard let userId = try? AppCoordinator.shared.requireUserId() else {
      return
    }
    // Only jobs with pay set up can take shifts. createShift rejects the rest.
    let configured: Set<String> = JobPaySetupStatusService.shared.configuredJobIds(for: userId)
    jobs = JobsRepository.shared.getActiveJobs(for: userId).filter { configured.contains($0.id) }
    selectedJobId = (jobs.first(where: \.is_default) ?? jobs.first)?.id
  }

  internal func fetchShifts() async {
    errorMessage = nil
    guard let url = ICSShiftParser.feedURL(from: link) else {
      errorMessage = String(localized: .calendarImportErrorInvalidLink)
      return
    }
    isWorking = true
    defer { isWorking = false }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
      else {
        throw URLError(.badServerResponse)
      }
      let text: String =
        String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
      foundShifts = ICSShiftParser.shifts(from: text)
      hasFetched = true
      refreshExistingShiftKeys()
      if foundShifts.isEmpty {
        errorMessage = String(localized: .calendarImportErrorNoShifts)
      }
    } catch {
      // The link is a personal token, so it stays out of the log.
      kLogger.error("Calendar feed fetch failed: \(error.localizedDescription)")
      errorMessage = String(localized: .calendarImportErrorFetchFailed)
    }
  }

  /// Saves the new shifts and returns the dates that got a shift.
  /// After a failure, running it again skips the shifts that were saved.
  internal func importShifts() async -> Set<String> {
    guard let userId = try? AppCoordinator.shared.requireUserId(), let jobId = selectedJobId else {
      return []
    }
    isWorking = true
    errorMessage = nil
    var createdDates: Set<String> = []
    // ponytail: one createShift per shift, each starting a sync. Fine for a schedule's worth of
    // shifts. Add a batch insert to the store actor if imports get into the hundreds.
    do {
      for shift in newShifts {
        guard let shiftDate = Date.fromISODateString(shift.date) else {
          continue
        }
        _ = try await ShiftsRepository.shared.createShift(
          userId: userId,
          jobId: jobId,
          shiftDate: shiftDate,
          startTime: shift.startTime,
          endTime: shift.endTime,
          creationMethod: "calendar_import"
        )
        createdDates.insert(shift.date)
      }
      Haptics.playShiftCreationSuccess()
    } catch {
      kLogger.error("Calendar import stopped: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
      Haptics.play(.error)
    }
    if !createdDates.isEmpty {
      NotificationCenter.default.postShiftsDidChange(
        context: .affecting(isoDates: Array(createdDates)))
    }
    refreshExistingShiftKeys()
    isWorking = false
    return createdDates
  }

  private func refreshExistingShiftKeys() {
    guard let userId = try? AppCoordinator.shared.requireUserId(), let selectedJobId else {
      existingShiftKeys = []
      return
    }
    existingShiftKeys = Set(
      ShiftsRepository.shared.getAllShifts(for: userId, jobId: selectedJobId).map { shift in
        "\(shift.shift_date) \(shift.start_time.prefix(5)) \(shift.end_time.prefix(5))"
      }
    )
  }
}

/// Sheet for importing shifts from a Planday, Quinyx, Tamigo or MinGat calendar link.
/// The link is not stored. Importing the same link again skips shifts that already exist.
internal struct CalendarImportView: View {
  /// Called with the dates that got a shift when an import finished without errors.
  internal var onImported: (Set<String>) -> Void = { _ in }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: CalendarImportModel = CalendarImportModel()

  private static let systemHelp: [(name: String, text: LocalizedStringResource)] = [
    ("Planday", .calendarImportHelpPlanday),
    ("Quinyx", .calendarImportHelpQuinyx),
    ("Tamigo", .calendarImportHelpTamigo),
    ("MinGat", .calendarImportHelpMingat),
  ]

  internal var body: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      Form {
        Group {
          linkSection

          if let errorMessage = model.errorMessage {
            Section {
              Text(errorMessage)
                .font(.tidexSubheadline)
                .foregroundColor(.tidexError)
                .announcesToVoiceOver(errorMessage)
            }
          }

          if model.hasFetched, !model.foundShifts.isEmpty {
            previewSections
          } else {
            helpSection
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
      .tidexListBackground()
      .navigationTitle(String(localized: .calendarImportTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
        }
      }
      .disabled(model.isWorking)
      .onChange(of: model.isWorking) { _, isWorking in
        if isWorking {
          AccessibilityNotification.Announcement(String(localized: .commonLoading)).post()
        }
      }
    }
    .onAppear {
      model.loadJobs()
    }
  }

  private var linkSection: some View {
    Section {
      TextField(String(localized: .calendarImportLinkPlaceholder), text: $model.link)
        .keyboardType(.URL)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .onSubmit { Task { await model.fetchShifts() } }

      Button {
        Task { await model.fetchShifts() }
      } label: {
        HStack {
          Text(.calendarImportFindButton)
          if model.isWorking, !model.hasFetched {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(model.link.trimmingCharacters(in: .whitespaces).isEmpty)
    } footer: {
      Text(.calendarImportIntro)
    }
  }

  private var helpSection: some View {
    Section {
      ForEach(Self.systemHelp, id: \.name) { system in
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(verbatim: system.name)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text(system.text)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
        }
        .accessibilityElement(children: .combine)
      }
    } header: {
      Text(.calendarImportHelpHeader)
    }
  }

  @ViewBuilder
  private var previewSections: some View {
    if model.jobs.count > 1 {
      Section {
        Picker(selection: $model.selectedJobId) {
          ForEach(model.jobs) { job in
            Text(verbatim: job.name).tag(Optional(job.id))
          }
        } label: {
          Text(.jobsFilterTitle)
        }
      }
    }

    Section {
      if model.newShifts.isEmpty {
        Text(.calendarImportNothingNew)
          .foregroundColor(.tidexTextSecondary)
      }
      ForEach(model.newShifts) { shift in
        VStack(alignment: .leading, spacing: 2) {
          Text(
            shift.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
          )
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          let detailLayout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: Spacing.xs))
          detailLayout {
            Text(shift.start..<shift.end, format: .interval.hour().minute())
            if let title = shift.title {
              Text(verbatim: title)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
          }
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
        }
        .accessibilityElement(children: .combine)
      }
    } header: {
      Text(.calendarImportShiftsHeader)
    } footer: {
      if model.duplicateCount > 0 {
        Text(.calendarImportDuplicatesSkipped(model.duplicateCount))
      }
    }

    if !model.newShifts.isEmpty {
      Section {
        Button {
          Task {
            let created: Set<String> = await model.importShifts()
            guard model.errorMessage == nil else {
              return
            }
            onImported(created)
            dismiss()
          }
        } label: {
          HStack {
            Text(.calendarImportImportButton(model.newShifts.count))
              .font(.tidexBodyMedium)
            if model.isWorking {
              Spacer()
              ProgressView()
            }
          }
        }
        .disabled(model.selectedJobId == nil)
      }
    }
  }
}

#Preview {
  CalendarImportView()
}
